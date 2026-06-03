# AI 拆卡治理与可调优生成 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把当前“AI 草稿生成”升级为“可配置规则、可验证质量、可批量微调”的拆卡系统，让长文档尤其是教材类内容能更稳定地生成符合背诵规律的卡片。

**Architecture:** 保持 AI 编排统一在 Go 服务端，但把“生成原则”从硬编码 prompt 提升为显式的 `GenerationPolicy`。服务端新增文档切块、候选校验、修复重写和批量生成工作流；Flutter 客户端新增规则模板编辑器和生成工作台，让用户能在生成前设规则、生成后批量微调，再决定是否入库。

**Tech Stack:** Flutter, Riverpod, Dio, Go/Gin, PostgreSQL, OpenAI-compatible chat completions, Card DSL, server-side validation heuristics, async job polling.

---

## 一、问题定义

### 1. 现在要解决什么问题

当前 AI 导入/生成已经能出草稿，但还不具备以下关键能力：

1. 不能稳定保证“一卡一知识点、答案短且可自评、题型和内容匹配”。
2. 不能可靠处理整本教材或长章节，容易因为上下文过长导致覆盖不全、粒度漂移或漏点。
3. 生成原则写死在服务端 prompt 中，用户无法看见、更无法按学科和用途进行配置。
4. 生成后只有“预览 + 保存”，缺少批量重写、批量缩短答案、批量拆卡、只修正不合格卡片等工作台能力。

### 2. 预期输入

支持三类输入：

1. 主题 + 用户补充背景文本。
2. 短文档：`pdf` / `txt` / `md`。
3. 长文档：教材、讲义、整章内容，可能需要切块和异步生成。

同时新增一类“规则输入”：

1. 选择已有规则模板。
2. 结构化编辑规则。
3. 填写高级自定义说明。

### 3. 预期输出

输出不再只是 `items`，而是完整的生成工作结果：

1. `document`：文档摘要、切块信息、页码/章节元信息。
2. `policy`：本次实际生效的规则快照。
3. `items`：生成的候选卡片。
4. `quality_report`：每张卡是否违反规则、违反了什么。
5. `warnings`：如“文档过长已截断”“存在重复概念”“部分章节未覆盖”。
6. 可选 `job_id`：长文档异步生成时用于轮询。

### 4. 副作用

1. 用户可保存/更新规则模板。
2. 用户可将 AI 草稿批量保存到牌组。
3. 长文档生成可能产生一次后台 job 记录及中间状态。

### 5. 必须保持不变的行为

1. 现有 `POST /api/v1/ai/generate`、`POST /api/v1/ai/import-file`、`POST /api/v1/ai/rewrite-card` 仍可兼容现有客户端字段。
2. Card DSL 仍是唯一的统一内容格式。
3. 现有单卡编辑、预览、保存、加入背诵流程保持可用。

### 6. 允许变化的行为

1. AI 文件导入可从同步返回升级为“短文档同步、长文档异步”双模式。
2. 生成结果返回结构可增加 `policy`、`quality_report`、`job` 信息。
3. AI 改写结果可从“单候选模板改写”升级为“多候选 + 质量标签”。

### 7. 设计假设

1. 用户愿意先确认草稿，再决定是否入库。
2. 绝大多数用户更需要“可解释的结构化规则”而不是纯 prompt engineering。
3. 当前仓库没有成熟的队列基础设施，因此异步 job 第一版优先走数据库持久化 + HTTP 轮询，不引入新中间件。

---

## 二、范围控制

### 本次设计覆盖

1. 规则模型与规则模板持久化。
2. 长文档切块生成工作流。
3. 生成后质量校验与修复。
4. 单卡与批量微调交互。
5. API、状态管理、测试与文档更新。

### 本次不做

1. OCR 扫描 PDF 识别。
2. 向量数据库或复杂语义召回。
3. 自动无确认入库。
4. 完整多人协作规则库。

### 可能修改的模块

1. `server/internal/model/model.go`
2. `server/internal/service/app.go`
3. `server/internal/service/ai_provider.go`
4. `server/internal/service/document_text.go`
5. `server/internal/handler/http.go`
6. `server/internal/repository/*`
7. `server/migrations/*`
8. `server/api/openapi.yaml`
9. `client/lib/core/network/api_client.dart`
10. `client/lib/core/app_store.dart`
11. `client/lib/app/screens.dart`
12. `client/lib/app/editor/card_editor_screen.dart`

### 公共 API 变化

会新增 API，并对原有 AI API 做向后兼容扩展：

1. 新增 `GET/POST/PUT/DELETE /api/v1/ai/policies`
2. 新增 `POST /api/v1/ai/generate-job`
3. 新增 `GET /api/v1/ai/generate-job/:id`
4. 扩展 `/ai/generate`、`/ai/import-file`、`/ai/rewrite-card`

### 数据库变化

需要新增表：

1. `ai_generation_policies`
2. `ai_generation_jobs`

### 新依赖

第一版不新增第三方依赖，优先复用现有 Go/Flutter 能力与自定义启发式校验。

---

## 三、现有系统分析

### 1. 入口点

1. 文本生成：`POST /api/v1/ai/generate`
2. 文件导入生成：`POST /api/v1/ai/import-file`
3. 单卡改写：`POST /api/v1/ai/rewrite-card`
4. 客户端 AI 生成页：`client/lib/app/screens.dart`
5. 编辑器 AI 优化弹层：`client/lib/app/editor/card_editor_screen.dart`

### 2. 当前架构边界

1. Handler：参数解析、鉴权、返回 JSON。
2. Service：AI prompt、模板回退、文档抽文本。
3. Repository：牌组/卡片/用户等存取。
4. Client Store：发请求、保存生成结果、最终落库。

### 3. 当前数据流

#### 当前短文本生成

`topic/context -> /ai/generate -> prompt -> 模型或模板回退 -> items -> 客户端预览 -> 保存为卡片`

#### 当前文件生成

`上传文件 -> 文本抽取 -> 直接把全文塞到 request.Context -> 复用 /ai/generate -> 返回 items + document`

#### 当前改写

`当前卡片 -> rewrite_type + instruction -> /ai/rewrite-card -> 候选 -> 应用回编辑器`

### 4. 当前主要缺口

1. `GenerationPolicy` 不存在，只有写死的 prompt 规则。
2. 文档没有章节/语义切块，全文直接喂模型。
3. 没有卡片质量校验器，无法自动判定“是否原子”“答案是否过长”“是否重复”。
4. 没有生成工作台，只有一次性预览。
5. 单卡 `split` 仍只返回单张候选，不是真正多卡拆分。

---

## 四、目标产品能力

### 1. 规则对用户可见

用户在生成前必须能看到并调整核心原则，而不是依赖黑盒 prompt。

### 2. 长文档稳定拆卡

系统应支持“按章节切块 -> 分块生成 -> 合并去重 -> 检查覆盖率”的链路。

### 3. 生成结果可批量治理

用户必须能在保存前批量处理：

1. 缩短答案
2. 转题型
3. 拆大卡
4. 重生成不合格卡
5. 只保存通过质量检查的卡

### 4. 单卡微调要顺手

保留现有 `AI 优化` 入口，但升级为真正可多轮使用的微调面板，而不是一次性模板按钮。

---

## 五、提议设计

## 5.1 GenerationPolicy：把生成原则变成一等公民

新增服务端模型 `GenerationPolicy`：

```text
id
user_id
name
description
subject
audience
atomicity_level            // strict | balanced | flexible
answer_style               // short_phrase | one_sentence | bullet_points
max_answer_chars
preferred_card_types       // basic/cloze/single_choice/multi_choice + ratio
allow_definition_cards
allow_comparison_cards
allow_example_cards
allow_misconception_cards
split_strategy             // by_heading | by_learning_objective | by_exam_point
coverage_mode              // key_points | balanced | exhaustive
max_cards_per_chunk
max_cards_total
require_source_excerpt
require_source_location
dedupe_level               // low | medium | high
repair_mode                // off | violations_only | always
custom_rules
created_at
updated_at
```

### 设计原则

1. 结构化字段优先，减少 prompt 不稳定性。
2. 保留 `custom_rules`，满足高级用户。
3. 所有生成请求都附带“规则快照”，便于复现。

### 客户端规则编辑器

前端不直接暴露原始 JSON，优先做结构化面板：

1. `原子性`：严格 / 平衡 / 灵活
2. `答案长度`：短词 / 一句话 / 三点以内
3. `偏好题型`：问答 / 填空 / 单选 / 多选
4. `覆盖方式`：核心考点 / 平衡覆盖 / 尽量完整
5. `拆分方式`：按标题 / 按知识目标 / 按考试点
6. `额外要求`：自由文本

并提供两个层级：

1. `规则模板`：通用、考试冲刺、概念课、语言记忆、教材精读
2. `高级设置`：可展开编辑细项

## 5.2 文档切块工作流：为教材类内容设计

新增 `document_chunker.go`，负责把抽出的长文本切成可生成的片段。

### 切块策略

#### Markdown / TXT

1. 优先按标题层级切段。
2. 标题下内容过长时按段落组块。
3. 每块附带 `heading_path`、`chunk_index`。

#### PDF

1. 尽量保留页码。
2. 先按页聚合，再按字数阈值合并相邻页。
3. 每块附带 `page_start/page_end`。

### 切块参数

```text
target_chars_per_chunk   = 2000~3500
hard_max_chars           = 5000
overlap_chars            = 150~300
max_chunks_per_job       = 24
```

### 为什么必须切块

整本《教育学原理》这种输入，如果仍走“全文一次 prompt”，会出现：

1. 上下文过长导致模型选择性忽略内容。
2. 卡片粒度不稳定。
3. 生成结果偏向前几章或常见概念。
4. 长耗时请求更容易超时失败。

## 5.3 生成模式：同步与异步并存

### 短输入

继续支持同步生成：

1. 用户输入简短主题/上下文。
2. 或导入单章、单篇讲义。

### 长输入

新增异步生成 job：

1. `POST /api/v1/ai/generate-job`
2. 服务端返回 `job_id`
3. 客户端轮询 `GET /api/v1/ai/generate-job/:id`
4. 状态：`pending/running/succeeded/failed/canceled`

### Job 存储字段

```text
id
user_id
source_name
source_type
policy_snapshot_json
request_json
status
progress
error_message
result_json
created_at
updated_at
```

### 为什么这里要异步

只要做分块生成和修复重写，请求耗时很容易超过当前同步 HTTP 体验的舒适区。对书籍类内容不引入异步，会让产品体验不稳定。

## 5.4 质量校验器：把“原则”从提示词变成可验证规则

新增 `card_candidate_validator.go`。

### 每张卡的校验维度

1. `atomicity`
   - 是否同时考多个并列概念
   - 是否题干过宽
2. `answer_length`
   - 是否超出规则允许长度
3. `self_checkable`
   - 答案是否可判断正误
4. `card_type_match`
   - 题型和内容是否匹配
5. `duplicate_risk`
   - 与已有候选是否高度重复
6. `source_traceability`
   - 是否保留来源摘录/位置

### 输出结构

```text
card_id
score
badges
violations[]
repairable
```

### 启发式即可，不追求第一版完美 NLP

第一版不做复杂模型判别，优先使用：

1. 字数阈值
2. 并列连接词检测
3. 问答/选项结构检查
4. 题干重复率
5. 与邻近卡片的 n-gram 重叠度

## 5.5 修复重写器：只修问题卡，而不是全量重来

当 `repair_mode != off` 时，服务端对违反规则但可修复的卡执行一次 repair pass。

### Repair 输入

1. 原始卡片 DSL
2. 生效规则快照
3. 违反项列表
4. 文档局部来源摘录

### Repair 输出

1. 修复后的单卡或多卡候选
2. 修复说明

### 典型修复场景

1. 大而全的定义卡 -> 拆成 2~3 张原子卡
2. 答案过长 -> 压缩为一句话
3. 题型不匹配 -> 改为填空/单选
4. 重复卡 -> 合并或丢弃一张

## 5.6 批量微调工作台：代替“一次性预览”

现有生成页升级为 `AI Draft Workspace`。

### 工作台分组

1. `全部`
2. `已通过`
3. `需修正`
4. `已选中`

### 卡片卡面展示

每张卡必须展示：

1. 题干预览
2. 答案预览
3. 题型
4. 质量徽章
5. 来源章节/页码
6. 是否违反规则

### 批量操作

1. `全部缩短答案`
2. `全部改为更原子`
3. `仅重生成不合格卡`
4. `选中卡改成填空`
5. `选中卡改成单选`
6. `选中卡按用户说明重写`
7. `仅保存通过项`

### 单卡操作

1. 编辑正文
2. 继续 AI 微调
3. 查看来源摘录
4. 拆成多张
5. 删除候选

## 5.7 编辑器内 AI 微调升级

保留现有 `AI 优化`，但升级为：

1. 支持多轮微调历史。
2. 支持“只改题干 / 只改答案 / 同时改”。
3. 支持“保留标签和备注”。
4. 支持“应用到当前卡”或“另存为新卡”。

`split` 类型必须真正支持多卡返回，而不是只给一张候选。

---

## 六、API 设计

### 6.1 规则模板 API

#### `GET /api/v1/ai/policies`

返回用户可见规则模板列表。

#### `POST /api/v1/ai/policies`

创建规则模板。

#### `PUT /api/v1/ai/policies/:id`

更新规则模板。

#### `DELETE /api/v1/ai/policies/:id`

删除规则模板。

### 6.2 生成 API 扩展

#### 扩展 `POST /api/v1/ai/generate`

新增字段：

```json
{
  "topic": "...",
  "context": "...",
  "card_count": 12,
  "difficulty": "medium",
  "policy_id": "optional",
  "policy": {},
  "batch_mode": false
}
```

#### 扩展 `POST /api/v1/ai/import-file`

新增字段：

1. `policy_id`
2. `policy_json`
3. `async_if_large`

### 6.3 异步生成 API

#### `POST /api/v1/ai/generate-job`

适合长文档/整本书。

#### `GET /api/v1/ai/generate-job/:id`

返回进度、摘要、结果或失败信息。

### 6.4 批量重写 API

新增：

#### `POST /api/v1/ai/rewrite-batch`

```json
{
  "policy_id": "...",
  "instruction": "把不合格卡全部压成一句话答案",
  "action": "simplify_answer",
  "cards": [...]
}
```

返回：

1. 新候选列表
2. 每张卡的变更摘要
3. 失败项

---

## 七、正确性论证

### 前置条件

1. 用户已登录。
2. 输入文本可成功抽取。
3. 规则模板可解析且字段合法。

### 成功后的后置条件

1. 每个候选卡都带有规则快照和质量报告。
2. 长文档生成结果可追溯到具体章节或页码范围。
3. 用户在保存前可看到哪些卡违反了规则。

### 不变量

1. Card DSL 仍是唯一卡片内容标准。
2. 未经用户确认，AI 候选不直接进入复习队列。
3. 任何自动 repair 都不能直接覆盖用户已编辑内容。

### 失败行为

1. 文档抽取失败：直接返回可理解错误。
2. 单块 AI 调用失败：标记该 chunk 失败，不污染其他 chunk。
3. repair pass 失败：保留原候选并标记“需要人工修正”。
4. job 中断：保留中间进度，允许重试。

### 兼容性

1. 老客户端仍可只传 `topic/context/card_count/difficulty`。
2. 老的 AI 改写页仍可只用默认规则。
3. 老生成结果 `front/back/content` 格式继续兼容。

### 幂等性

1. 规则模板 CRUD 以资源 ID 保证幂等更新。
2. job 创建可附带 `client_request_id`，避免重复提交同一本书。
3. 最终保存卡片仍沿用现有 `createCard`/`client_id` 逻辑。

---

## 八、可维护性与扩展点

### 服务端新增模块建议

1. `server/internal/service/generation_policy.go`
2. `server/internal/service/document_chunker.go`
3. `server/internal/service/card_candidate_validator.go`
4. `server/internal/service/ai_generation_jobs.go`

### 客户端新增模块建议

1. `client/lib/app/ai/generation_policy_editor.dart`
2. `client/lib/app/ai/draft_workspace.dart`
3. `client/lib/app/ai/quality_badges.dart`

### 扩展点

1. 后续可增加 OCR。
2. 后续可增加学科模板市场。
3. 后续可增加“根据错题记录反向优化生成规则”。

---

## 九、分阶段实施建议

### Phase 1：规则显式化 + 质量标签 + 单卡/批量微调基础

目标：先把“原则可见、可配置、可检查”立起来，不先碰复杂异步。

包含：

1. `GenerationPolicy` 模型与默认模板
2. 前端规则编辑器
3. 同步生成链路接收 `policy`
4. 候选质量报告
5. 生成工作台基础版
6. 单卡和批量 rewrite 基础版

### Phase 2：长文档切块 + 异步 job

目标：让教材/长章节场景可用。

包含：

1. 文档切块器
2. 异步 job 表和轮询 API
3. chunk 级别进度反馈
4. 分块去重与合并

### Phase 3：repair pass + 规则驱动再生成

目标：让系统能主动修不合格卡，减少人工整理。

包含：

1. 违规卡 repair pass
2. “仅重生成不合格卡”
3. “按规则重新平衡题型”

---

## 十、实施任务

### Task 1：定义规则模型与默认模板

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/core/network/api_client.dart`
- Test: `server/internal/service/app_test.go`

**Steps:**
1. 增加 `GenerationPolicy`、`GenerationPolicySummary`、`GenerationQualityReport`、`AIGenerationJob` 等模型。
2. 给 AI 请求与响应增加 `policy_id`、`policy`、`quality_report`、`warnings`。
3. 保持旧字段兼容。
4. 补齐默认模板的序列化测试。

### Task 2：新增规则模板存储与 API

**Files:**
- Modify: `server/internal/repository/store.go`
- Modify: `server/internal/repository/memory.go`
- Modify: `server/internal/repository/postgres.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`
- Modify: `server/api/openapi.yaml`
- Create: `server/migrations/003_ai_generation_policies.up.sql`
- Create: `server/migrations/003_ai_generation_policies.down.sql`
- Test: `server/internal/repository/memory_test.go`

**Steps:**
1. 新增 `ai_generation_policies` 表。
2. 实现 CRUD repository。
3. 暴露 `GET/POST/PUT/DELETE /ai/policies`。
4. 增加 handler/service 测试。

### Task 3：实现文档切块器

**Files:**
- Create: `server/internal/service/document_chunker.go`
- Modify: `server/internal/service/document_text.go`
- Test: `server/internal/service/document_text_test.go`

**Steps:**
1. 为 TXT/MD/PDF 文本构建带位置信息的 section/chunk。
2. 为 chunk 增加标题路径或页码范围。
3. 编写长文档切块测试，覆盖标题切块、页码切块、超长段落回退。

### Task 4：让生成链路真正吃规则与 chunk

**Files:**
- Modify: `server/internal/service/ai_provider.go`
- Modify: `server/internal/service/app.go`
- Test: `server/internal/service/app_test.go`

**Steps:**
1. 用 `GenerationPolicy` 替代硬编码规则片段。
2. 为每个 chunk 构建更窄上下文 prompt。
3. 合并 chunk 结果并限制总卡数。
4. 保持外部 AI 与模板回退两条链路都能工作。

### Task 5：实现候选质量校验器

**Files:**
- Create: `server/internal/service/card_candidate_validator.go`
- Modify: `server/internal/service/app.go`
- Test: `server/internal/service/app_test.go`

**Steps:**
1. 为每张卡输出 `score/badges/violations`。
2. 实现原子性、答案长度、题型匹配、重复风险等启发式检查。
3. 把质量报告挂到生成结果。

### Task 6：实现批量改写与 repair pass

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `server/internal/service/ai_provider.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`
- Modify: `server/api/openapi.yaml`
- Test: `server/internal/service/app_test.go`

**Steps:**
1. 让 `split` 支持返回多卡。
2. 新增 `/ai/rewrite-batch`。
3. 为不合格卡增加一次可选 repair pass。
4. 保证 repair 不直接覆盖原始候选。

### Task 7：实现长文档异步 job

**Files:**
- Modify: `server/internal/repository/store.go`
- Modify: `server/internal/repository/memory.go`
- Modify: `server/internal/repository/postgres.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`
- Modify: `server/api/openapi.yaml`
- Create: `server/migrations/004_ai_generation_jobs.up.sql`
- Create: `server/migrations/004_ai_generation_jobs.down.sql`
- Test: `server/internal/service/app_test.go`

**Steps:**
1. 新增 `ai_generation_jobs` 表。
2. 实现 `create/get/update-progress` repository。
3. 提供 `POST /ai/generate-job` 和 `GET /ai/generate-job/:id`。
4. 客户端轮询完成后再拉取完整结果。

### Task 8：客户端规则编辑器与生成工作台

**Files:**
- Modify: `client/lib/app/screens.dart`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/core/network/api_client.dart`
- Create: `client/lib/app/ai/generation_policy_editor.dart`
- Create: `client/lib/app/ai/draft_workspace.dart`
- Test: `client/test/ai/ai_generate_screen_test.dart`

**Steps:**
1. 新增规则模板下拉与“编辑规则”入口。
2. 生成结果页升级为工作台，支持过滤与批量操作。
3. 展示质量徽章、来源位置和警告信息。
4. 为保存前批量治理编写 widget test。

### Task 9：升级编辑器内 AI 微调体验

**Files:**
- Modify: `client/lib/app/editor/card_editor_screen.dart`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/core/network/api_client.dart`
- Test: `client/test/editor/card_editor_screen_test.dart`

**Steps:**
1. 支持局部应用候选内容。
2. 支持多卡 `split` 候选。
3. 支持“另存为新卡”。
4. 保证移动端和窄屏下交互仍可用。

### Task 10：全量验证

**Files:**
- Test: `server/internal/service/*_test.go`
- Test: `client/test/**`

**Steps:**
1. 运行 `cd server && go test ./...`
2. 运行 `cd client && flutter analyze`
3. 运行 `cd client && flutter test -r compact`
4. 人工验证：
   - 章节级文档生成
   - 长文档异步生成
   - 批量缩短答案
   - 单卡拆分
   - 保存前过滤不合格卡

---

## 十一、产品验收标准

满足以下条件后，才认为这套设计真正解决了你的问题：

1. 用户能清楚看到并修改卡片生成原则。
2. 给“教育学原理”一章内容，系统能稳定拆出原子卡，并标记不合格项。
3. 给整本书时，系统不会因为上下文过长而直接退化为黑盒随机拆卡。
4. 用户能在保存前批量微调，而不是逐张手工修。
5. 微调后的操作链路在手机和桌面上都不别扭。

# Server FSRS And UI Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 移除客户端离线 FSRS 调度，把复习评分统一交给服务端官方 FSRS，并顺手提升 Ank 客户端 UI 的清晰度、复习体验和功能入口完整度。

**Architecture:** 客户端保留 FSRS 状态模型用于展示和反序列化，但不再在离线情况下自行计算下一次复习时间；提交评分必须请求服务端，失败时保留当前卡片状态并提示联网重试。UI 优化按低风险路径推进：先修信息架构与入口，再打磨复习页、首页、编辑器和统计页，不重写现有状态管理。

**Tech Stack:** Flutter/Dart、Riverpod、Go、go-fsrs/v4、flutter test、flutter analyze、go test

---

### Task 1: 明确联网优先产品策略

**Files:**
- Modify: `README.md`
- Modify: `client/README.md`
- Modify: `docs/plans/2026-05-17-server-fsrs-and-ui-polish.md`

**Step 1: 更新产品说明**

把“离线可用 / 离线复习结果保存”从核心卖点里降级或删除，明确当前复习调度以服务端为准。

建议 README 方向：

```markdown
- 服务端 FSRS 复习调度
- 客户端本地缓存用于启动加速和弱网查看
- 复习评分需联网提交，避免跨端调度漂移
```

**Step 2: 检查 UI 文案**

搜索：

```bash
rg -n "离线|离线可用|离线保存|待同步|自动同步|网络恢复" README.md client/README.md client/lib
```

将“离线复习可用”的表述改为“联网同步 / 弱网缓存 / 待同步编辑操作”。

**Step 3: 验证**

Run:

```bash
rg -n "离线可用|复习结果已离线保存" README.md client/README.md client/lib
```

Expected: 不再出现会暗示离线 FSRS 复习可用的文案。

---

### Task 2: 移除客户端离线 FSRS 计算路径

**Files:**
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/test/core/fsrs_scheduler_test.dart`
- Modify: `client/test/core/review_queue_test.dart`

**Step 1: 写失败测试**

在 `client/test/core/review_queue_test.dart` 或新增 `client/test/core/submit_review_online_test.dart` 中覆盖：

```dart
test('submit review does not mutate fsrs state when offline', () async {
  // Given: one due review card with known state
  // When: API submitReview throws a network DioException
  // Then: card.state is unchanged and user sees retry/network error
});
```

如果现有 `AppStore` 难以注入 fake `ApiClient`，先做一个小型依赖注入改造，让测试可以传入 fake client。

**Step 2: 删除离线调度分支**

在 `AppStore.submitReview` 的 `DioException` 分支中移除：

```dart
final FsrsState nextState = _fsrsScheduler.review(...);
```

失败时不要 upsert 更新后的本地卡片，不要 enqueue `submit_review` 操作。改为：

```dart
state = state.copyWith(errorMessage: '提交评分需要联网，请检查网络后重试');
```

**Step 3: 保留可恢复编辑同步**

不要删除建卡、改卡、删卡等内容编辑的待同步队列，除非产品也决定全部强联网。当前建议只取消“复习评分离线同步”，因为评分会改变 FSRS 排期，最容易产生跨端漂移。

**Step 4: 调整测试期望**

删除或改写那些断言离线 submit review 会更新本地 FSRS 状态的测试。

**Step 5: 验证**

Run:

```bash
cd client && flutter test -r compact test/core
cd client && flutter analyze
```

Expected: 全部通过。

---

### Task 3: 精简客户端 FSRS Scheduler 的职责

**Files:**
- Modify: `client/lib/core/fsrs_scheduler.dart`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/test/core/fsrs_scheduler_test.dart`

**Step 1: 搜索调用点**

Run:

```bash
rg -n "FsrsScheduler|\\.review\\(|initStability|nextInterval|calculateRetrievability" client/lib client/test
```

**Step 2: 删除客户端算法实现**

如果移除离线评分后没有业务调用 `FsrsScheduler.review`，将 `fsrs_scheduler.dart` 收缩为：

```dart
enum ReviewRating { again(1), hard(2), good(3), easy(4); ... }

class FsrsState {
  const FsrsState({...});
  final int state;
  final double difficulty;
  final double stability;
  final double retrievability;
  final DateTime dueDate;
  final DateTime? lastReviewAt;
  final int reps;
  final int lapses;
  final double elapsedDays;
  final double scheduledDays;

  bool get isDue => !dueDate.isAfter(DateTime.now());
}
```

也就是客户端只保留状态和评分枚举，不保留调度数学。

**Step 3: 删除算法单测**

删除或重命名 `client/test/core/fsrs_scheduler_test.dart` 中官方序列匹配测试，因为客户端不再拥有算法责任。保留轻量模型测试即可：

```dart
test('ReviewRating.fromScore parses valid scores', () { ... });
test('FsrsState.isDue reflects dueDate', () { ... });
```

**Step 4: 验证**

Run:

```bash
cd client && flutter test -r compact test/core
cd client && flutter analyze
```

Expected: 全部通过，且 `rg "FsrsScheduler"` 无业务调用。

---

### Task 4: 服务端 FSRS 成为唯一调度源

**Files:**
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/pkg/fsrs/algorithm_test.go`
- Modify: `server/internal/service/app_test.go`
- Modify: `server/api/openapi.yaml`

**Step 1: 补服务端契约测试**

新增或扩展测试：

```go
func TestSubmitReviewUsesServerFSRSAndReturnsUpdatedCard(t *testing.T) {
  // create study-enabled due card
  // submit Good
  // assert card.State.Reps == 1
  // assert card.State.DueDate.After(reviewedAt)
  // assert review log is appended
}
```

**Step 2: 确认离线 sync 不再接受 submit_review**

如果客户端已经不再提交 `submit_review` sync operation，可以考虑让服务端 `SyncPush` 对 `submit_review` 返回明确错误：

```go
recordFailure("submit_review must be sent through /reviews")
```

更保守的做法是先保留兼容 1 个版本，避免旧客户端升级期间丢数据。建议本项目当前阶段可以直接移除或标记 deprecated。

**Step 3: 更新 OpenAPI**

在 `server/api/openapi.yaml` 里明确：

```yaml
description: Submit a review rating online. Scheduling is calculated by the server FSRS engine.
```

**Step 4: 验证**

Run:

```bash
cd server && go test ./...
```

Expected: 全部通过。

---

### Task 5: UI 文案与信息架构整理

**Files:**
- Modify: `client/lib/app/screens.dart`
- Modify: `client/lib/app/theme/app_theme.dart`

**Step 1: 首页重新聚焦学习任务**

首页首屏目标调整为“今天该做什么”，而不是泛泛展示产品能力。

建议首页模块顺序：

1. 今日复习摘要：待复习、今日完成、下一个到期时间。
2. 快速动作：开始复习、新建卡片、导入 DSL。
3. 学习空间：文件夹和牌组。
4. 同步状态：弱化为顶部/底部提示，不抢主视觉。

**Step 2: 删除产品营销式文案**

登录页和首页减少“AI、同步、跨端”等宣传语，改成用户任务语言。

示例：

```dart
title: '今天要复习的内容'
subtitle: dueCards == 0 ? '暂时没有到期卡片' : '先完成到期卡片，再补充新内容'
```

**Step 3: 统一状态提示**

把 `_InfoPanel` 的使用分级：

- error: 红色，阻断或失败
- warning: 待同步、弱网
- info: 空状态提示
- success: 完成状态

避免所有提示都像同等重要。

**Step 4: 验证**

Run:

```bash
cd client && flutter test -r compact test/home
cd client && flutter analyze
```

Expected: 首页测试通过，分析无问题。

---

### Task 6: 复习页交互优化

**Files:**
- Modify: `client/lib/app/screens.dart`
- Modify: `client/test/core/review_queue_test.dart`
- Modify: `client/test/widget_test.dart` 或新增 `client/test/review/review_screen_test.dart`

**Step 1: 增加联网状态保护**

评分按钮提交时增加 loading 状态，防止重复点击：

```dart
ReviewRating? _submittingRating;
```

点击评分后禁用四个按钮，成功后切下一张，失败时保留当前卡片并显示错误。

**Step 2: 评分失败不前进**

测试：

```dart
testWidgets('review screen keeps current card when submit fails', (tester) async {
  // fake store submitReview fails
  // tap Good
  // expect same card still visible
  // expect network retry message
});
```

**Step 3: 评分按钮适配窄屏**

当前四个按钮在很窄屏上横排容易拥挤。改为：

- >= 600px: 横排四按钮
- < 600px: 2x2 网格

**Step 4: 增加下一次复习反馈**

服务端返回更新后的卡片后，可以短暂 toast：

```text
已记录，下一次：明天 09:30
```

这会增强用户对 FSRS 的信任。

**Step 5: 验证**

Run:

```bash
cd client && flutter test -r compact
cd client && flutter analyze
```

Expected: 全部通过。

---

### Task 7: 编辑器体验优化

**Files:**
- Modify: `client/lib/app/editor/card_editor_screen.dart`
- Modify: `client/test/editor/card_editor_screen_test.dart`
- Modify: `client/test/editor/inline_style_application_test.dart`

**Step 1: 明确“加入背诵”的默认策略**

现在新卡默认 `_studyEnabled = false`。如果用户创建的是学习卡片，默认不进入复习队列可能让人困惑。建议改为：

```dart
_studyEnabled = true;
```

或者在保存后给明确提示：“已保存为草稿，打开加入背诵后会进入复习队列。”

更推荐默认 true，并允许用户切为草稿。

**Step 2: 保存后反馈**

创建/编辑成功后返回牌组页前显示短反馈，或者在牌组页顶部显示“卡片已保存”。

**Step 3: 预览入口更强**

把预览按钮放在编辑器顶部 toolbar 右侧，同时底部保留保存主按钮。用户写复杂 DSL/选择题时更容易来回检查。

**Step 4: 验证**

Run:

```bash
cd client && flutter test -r compact test/editor
cd client && flutter analyze
```

Expected: 编辑器测试通过。

---

### Task 8: 补齐 AI 生成功能入口

**Files:**
- Modify: `client/lib/app/screens.dart`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/test/widget_test.dart` 或新增 `client/test/ai/ai_generate_screen_test.dart`

**Step 1: 决定入口位置**

当前 `AppStore.generateCards` 和服务端 `/ai/generate` 存在，但 UI 没入口。建议在牌组详情页加：

- AppBar action: `Icons.auto_awesome_outlined`
- Empty state secondary action: `AI 生成`
- 新建卡片按钮旁的 overflow menu: `AI 生成卡片`

**Step 2: 新增生成 Sheet**

字段：

- topic: 主题
- context: 补充背景
- cardCount: 生成数量
- difficulty: 难度

生成后展示草稿列表，允许“保存到当前牌组”。

**Step 3: 默认不自动加入背诵**

AI 生成内容建议先作为草稿，用户确认后再加入背诵。保存时可以提供 checkbox：

```text
保存后加入背诵
```

**Step 4: 验证**

Run:

```bash
cd client && flutter test -r compact
cd client && flutter analyze
cd server && go test ./...
```

Expected: 全部通过。

---

### Task 9: 统计页升级为学习仪表盘

**Files:**
- Modify: `client/lib/app/screens.dart`
- Modify: `server/internal/service/app.go` 可选
- Modify: `server/internal/repository/store.go` 可选

**Step 1: 先做客户端本地可得指标**

不新增后端 API 的第一版：

- 今日完成
- 今日剩余
- 已加入背诵卡片数
- 草稿卡片数
- 到期卡片按牌组分布
- 未来 7 天 due count 预估

**Step 2: 后续服务端增强**

如果需要真实历史趋势，再新增 review log stats API：

```http
GET /api/v1/stats/reviews?days=30
```

返回每日 review count、Again/Hard/Good/Easy 分布。

**Step 3: 验证**

Run:

```bash
cd client && flutter test -r compact
cd client && flutter analyze
```

Expected: 全部通过。

---

### Task 10: 最终全量验证

**Files:**
- No direct file changes

**Step 1: 运行服务端测试**

```bash
cd server && go test ./...
```

Expected: PASS.

**Step 2: 运行客户端测试**

```bash
cd client && flutter test -r compact
```

Expected: PASS.

**Step 3: 静态分析**

```bash
cd client && flutter analyze
```

Expected: No issues found.

**Step 4: 手动冒烟**

启动本地服务：

```bash
bash scripts/start_local.sh
```

检查：

1. 登录 demo 账号。
2. 创建牌组。
3. 创建卡片，默认加入背诵。
4. 开始复习并提交 Good。
5. 断网或停后端时提交评分，确认不会本地推进 FSRS。
6. 重新联网后评分成功，卡片 due date 由服务端返回。

---

## Additional Optimization Backlog

- **认证体验:** 登录页增加“正在登录/注册” loading 和防重复提交。
- **错误处理:** 全局错误分层，网络错误、认证过期、服务端错误用不同文案。
- **空状态:** 首页、牌组详情、复习完成页都给下一步主按钮，避免用户卡住。
- **可访问性:** 评分按钮、图标按钮补充语义标签；颜色状态不要只靠颜色区分。
- **窄屏适配:** 复习四评分按钮、牌组设置 sheet、编辑器 toolbar 重点检查 320-390px 宽度。
- **导航一致性:** 从创建/导入/AI 生成返回后，保留用户所在牌组上下文。
- **数据一致性:** 内容编辑可以继续离线队列，但评分不建议离线队列；两者在 UI 文案上要明确区分。
- **测试质量:** 为 AppStore 注入 ApiClient/LocalCache fake，降低 widget 测试成本。
- **服务端兼容:** 如果有旧客户端，`sync submit_review` 先保留兼容并记录 deprecated；无旧客户端可直接拒绝。
- **性能:** 首页 `dueCountForDeck` 会多次计算 due 队列，牌组多时可缓存一次结果。
- **视觉系统:** 当前卡片圆角偏大，若想更工具化，可统一降到 12-16；重点操作按钮用更稳定的层级。
- **国际化:** 当前中文硬编码可接受；如果后续开源或多语言，提前抽取 l10n。

## Execution Result

- 客户端已移除离线 FSRS 调度实现，只保留 `ReviewRating` 与 `FsrsState` 数据模型。
- 复习评分现在必须联网提交，成功后使用服务端返回的卡片状态；网络失败不会本地推进状态，也不会新增 `submit_review` 待同步操作。
- 复习页增加评分提交中的 loading/禁用状态，失败时保留当前卡片并显示错误提示；评分按钮在窄屏下自动换成 2x2。
- 编辑器新建卡片默认加入背诵，减少“保存后为什么没有进入复习”的困惑。
- 牌组详情页已补齐 AI 生成入口，可以生成草稿、预览结果，并选择保存后是否加入背诵。
- 统计页已升级为学习仪表盘，增加背诵覆盖、下一张到期、未来 7 天负载和牌组待复习分布。
- README、客户端 README、登录页和 OpenAPI 已更新，明确服务端是 FSRS 排期唯一来源。

## Verification

- `cd client && flutter analyze`
- `cd client && flutter test -r compact`
- `cd server && go test ./...`

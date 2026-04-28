# Flashcard Round 3 Fullstack Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在已可登录联调的基础上，继续补齐同步能力、客户端体验、AI 生成入口和本地部署脚本，使项目从 MVP 走向可持续迭代的完整开发态。

**Architecture:** 服务端继续保持 Gin + Service + Repository 分层，在现有牌组/卡片/复习 API 上补 `sync` 与 `ai` 入口。客户端保持单仓 Flutter 架构，在 `AppStore` 上加入本地离线队列、远端同步与生成能力，并在现有页面中渐进增强交互，不重写整体 UI。

**Tech Stack:** Flutter, Riverpod, Dio, SQLite, Go, Gin, PostgreSQL, Bash

---

### Task 1: 同步主链路

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/core/database/local_cache.dart`
- Modify: `client/lib/core/network/api_client.dart`

**Step 1: 服务端新增 sync push/pull**

支持客户端上传本地待同步操作，并获取最新 decks/cards 快照。

**Step 2: 客户端新增离线操作队列**

至少缓存：
- create_card
- submit_review

**Step 3: 启动和刷新时自动同步**

登录后、拉取后、手动刷新时都会尝试推送待同步操作并拉最新快照。

### Task 2: 体验增强

**Files:**
- Modify: `client/lib/app/screens.dart`

**Step 1: 牌组详情支持搜索**

按卡片正反面和标签过滤。

**Step 2: 卡片页显示同步状态和操作反馈**

例如同步中、同步失败、离线排队。

**Step 3: 统计页补充更多指标**

例如待复习、新卡数、牌组分布。

### Task 3: AI 生成

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`
- Modify: `client/lib/core/network/api_client.dart`
- Modify: `client/lib/app/screens.dart`

**Step 1: 服务端新增 AI 生成接口**

先实现规则式/模板式生成，保留后续接外部模型的扩展位。

**Step 2: 客户端新增生成入口**

在创建卡片页输入主题后生成候选卡片。

**Step 3: 支持一键填充**

点击候选即填入表单，减少手工录入。

### Task 4: 部署与运行

**Files:**
- Create: `scripts/start_local.sh`
- Create: `scripts/stop_local.sh`
- Create: `.env.example`
- Modify: `README.md`

**Step 1: 补一键本地启动脚本**

包含数据库、后端、客户端 Web 的开发启动说明。

**Step 2: 补环境变量示例**

让新环境更容易复现。

### Task 5: 验证

**Files:**
- Verify: `client/`
- Verify: `server/`

**Step 1: Flutter 自检**

Run:
- `flutter analyze`
- `flutter test`

**Step 2: Go 自检**

Run:
- `gob121`

**Step 3: 联调验证**

至少验证：
- 登录后自动拉取
- 创建卡片成功并入本地缓存
- review 成功并更新状态
- 生成卡片候选可填入表单

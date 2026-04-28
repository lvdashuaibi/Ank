# Flashcard Round 4 Sync/AI/Batch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在第三轮基础上继续补齐完整同步协议、批量卡片操作，以及可切换到真实模型服务的 AI 生成能力。

**Architecture:** 服务端继续保持现有分层，在 sync 协议里补 `update_card`、`delete_card`，并为 AI 增加“外部模型优先，模板回退”的 Provider。客户端在当前状态层上补批量删除、批量保存 AI 草稿、离线删除排队和更清晰的同步体验。

**Tech Stack:** Flutter, Riverpod, Dio, SQLite, Go, Gin, PostgreSQL, HTTP

---

### Task 1: 完整同步协议

**Files:**
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/model/model.go`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/core/database/local_cache.dart`

**Step 1: 服务端支持 update/delete sync 操作**

支持：
- `create_card`
- `update_card`
- `delete_card`
- `submit_review`

**Step 2: 客户端支持离线删除排队**

删除失败时排队，恢复网络后自动补传。

### Task 2: 批量卡片能力

**Files:**
- Modify: `client/lib/app/screens.dart`
- Modify: `client/lib/core/app_store.dart`

**Step 1: 牌组详情支持多选**

支持选择多张卡片并批量删除。

**Step 2: AI 草稿支持批量入库**

将所有候选一键保存到当前牌组。

### Task 3: 可切真实 AI

**Files:**
- Modify: `server/internal/config/config.go`
- Create: `server/internal/service/ai_provider.go`
- Modify: `server/internal/service/app.go`
- Modify: `.env.example`

**Step 1: 增加 AI 配置项**

支持：
- `AI_BASE_URL`
- `AI_API_KEY`
- `AI_MODEL`

**Step 2: 外部模型优先**

配置存在时调用真实模型；失败时回退模板生成。

### Task 4: 验证

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

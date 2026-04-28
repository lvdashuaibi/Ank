# Flashcard Round 2 Data/Auth Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在现有 MVP 基础上补齐 PostgreSQL 服务端持久化、Flutter 客户端 SQLite 缓存、正式登录注册页面与真实 API 调用链路。

**Architecture:** 服务端抽象统一 `Store` 接口，保留内存实现并新增 PostgreSQL 实现，通过配置切换。客户端在 `AppStore` 上层补 `Auth + API + SQLite cache`，启动时先恢复本地登录态，再从远端加载数据并同步到本地缓存。

**Tech Stack:** Flutter, Riverpod, Dio, SQLite, Go, Gin, PostgreSQL, pgx, Docker Compose

---

### Task 1: 服务端持久化抽象

**Files:**
- Modify: `server/internal/repository/memory.go`
- Create: `server/internal/repository/store.go`
- Create: `server/internal/repository/postgres.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/cmd/server/main.go`

**Step 1: 抽象统一 Store 接口**

覆盖用户、牌组、卡片、到期查询、复习日志等核心读写。

**Step 2: 新增 PostgreSQL 实现**

使用 `database/sql + pgx` 实现 CRUD，并兼容当前 handler/service。

**Step 3: 启动时按配置选择 Store**

默认 `memory`，开发环境支持切换到 `postgres`。

### Task 2: 开发环境与迁移

**Files:**
- Create: `docker-compose.dev.yml`
- Modify: `server/migrations/001_init.up.sql`
- Modify: `server/migrations/001_init.down.sql`
- Modify: `server/internal/config/config.go`

**Step 1: 提供本地 PostgreSQL 开发编排**

包含 `postgres`，预留 Redis 端口。

**Step 2: 完善建表语句**

至少覆盖：
- users
- decks
- cards
- review_logs

**Step 3: 补充数据库配置**

支持：
- driver
- database_url
- auto_migrate

### Task 3: 客户端正式鉴权

**Files:**
- Modify: `client/pubspec.yaml`
- Create: `client/lib/core/auth/*`
- Modify: `client/lib/app/router.dart`
- Modify: `client/lib/app/screens.dart`

**Step 1: 新增登录/注册页面**

支持邮箱、密码、显示名。

**Step 2: 新增 token 存储**

优先使用安全存储；启动时恢复登录态。

**Step 3: 增加鉴权守卫**

未登录先进入登录页，登录成功进入牌组页。

### Task 4: 客户端真实 API

**Files:**
- Create: `client/lib/core/network/*`
- Modify: `client/lib/core/app_store.dart`

**Step 1: 封装 API Client**

支持：
- register
- login
- list decks
- list cards
- create card
- due cards
- submit review

**Step 2: 将 AppStore 改为远端优先 + 本地回写**

登录后拉取远端数据并刷新状态。

### Task 5: 客户端 SQLite 缓存

**Files:**
- Create: `client/lib/core/database/*`
- Modify: `client/lib/core/app_store.dart`

**Step 1: 创建本地表**

至少缓存：
- decks
- cards
- auth session

**Step 2: 启动时先加载缓存**

保证弱网下仍可看到最近数据。

**Step 3: 远端成功后回写缓存**

形成最小离线基础能力。

### Task 6: 验证

**Files:**
- Verify: `client/`
- Verify: `server/`

**Step 1: Flutter 自检**

Run:
- `flutter pub get`
- `flutter analyze`
- `flutter test`

**Step 2: Go 自检**

Run:
- `go mod tidy`
- `gob121`

**Step 3: 联调验证**

至少验证：
- 注册
- 登录
- 拉牌组
- 创建卡片
- 提交复习评分

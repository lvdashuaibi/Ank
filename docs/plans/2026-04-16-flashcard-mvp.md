# Flashcard MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 交付一个基于设计文档的闪卡项目 MVP 基础版，包含 `client/` Flutter 客户端与 `server/` Go 后端骨架、FSRS 核心能力与牌组/卡片/复习主流程。

**Architecture:** 仓库拆分为 `client/` 与 `server/` 两个顶级目录。客户端采用 Flutter + Riverpod + GoRouter，先落本地可运行页面骨架和简化数据流；后端采用 Gin 分层结构，先落配置、路由、模型、服务、内存仓储和迁移文件，确保接口可运行并为后续 PostgreSQL 接入留出稳定边界。

**Tech Stack:** Flutter, Dart, Riverpod, GoRouter, Gin, Zap, Viper, UUID, Go

---

### Task 1: 仓库初始化

**Files:**
- Create: `client/`
- Create: `server/`
- Create: `docs/plans/2026-04-16-flashcard-mvp.md`

**Step 1: 初始化 Flutter 项目**

Run: `flutter create --org com.ank --project-name flashcard_app client`

**Step 2: 初始化 Go 项目结构**

Create:
- `server/cmd/server/main.go`
- `server/internal/...`
- `server/go.mod`

**Step 3: 写入基础忽略与说明文件**

Create:
- `README.md`
- `server/README.md`

### Task 2: 客户端基础架构

**Files:**
- Modify: `client/pubspec.yaml`
- Create: `client/lib/app/`
- Create: `client/lib/core/`
- Create: `client/lib/features/`

**Step 1: 增加路由、状态管理、工具依赖**

Add minimal packages:
- `flutter_riverpod`
- `go_router`
- `uuid`
- `intl`

**Step 2: 搭建 App Shell**

Create:
- `client/lib/main.dart`
- `client/lib/app/app.dart`
- `client/lib/app/router.dart`
- `client/lib/app/theme/*`

**Step 3: 搭建页面骨架**

Create:
- 牌组列表页
- 牌组详情页
- 卡片编辑页
- 复习页
- 统计页
- 设置页

### Task 3: FSRS 核心实现

**Files:**
- Create: `client/lib/core/fsrs/*`
- Create: `server/internal/pkg/fsrs/*`

**Step 1: 实现通用状态模型**

Create Dart/Go 两侧的状态、评分、调度模型。

**Step 2: 实现基础调度算法**

覆盖：
- retrievability
- init difficulty/stability
- recall / forget update
- next interval

**Step 3: 增加最小验证**

Create:
- `server/internal/pkg/fsrs/algorithm_test.go`

### Task 4: 后端基础接口

**Files:**
- Create: `server/internal/config/config.go`
- Create: `server/internal/handler/*.go`
- Create: `server/internal/service/*.go`
- Create: `server/internal/repository/*.go`
- Create: `server/internal/model/*.go`

**Step 1: 搭建健康检查和 API 路由**

Expose:
- `GET /healthz`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET/POST/PUT/DELETE /api/v1/decks`
- `GET/POST/PUT/DELETE /api/v1/cards`
- `GET /api/v1/review/due`
- `POST /api/v1/review/submit`

**Step 2: 实现内存仓储 MVP**

为用户、牌组、卡片、FSRS 状态和复习日志提供线程安全内存实现。

**Step 3: 预留迁移文件**

Create:
- `server/migrations/001_init.up.sql`
- `server/migrations/001_init.down.sql`

### Task 5: 客户端主流程联动

**Files:**
- Create: `client/lib/features/deck/...`
- Create: `client/lib/features/card/...`
- Create: `client/lib/features/review/...`

**Step 1: 内置假数据与仓储**

先用本地仓储跑通 UI 流程。

**Step 2: 接入后端客户端**

封装最小 API client，支持牌组、卡片、复习查询与提交。

**Step 3: 跑通核心流程**

支持：
- 浏览牌组
- 查看牌组内卡片
- 新建卡片
- 开始复习
- 提交评分并更新进度

### Task 6: 验证

**Files:**
- Verify: `client/`
- Verify: `server/`

**Step 1: Flutter 自检**

Run:
- `flutter pub get`
- `flutter analyze`

**Step 2: Go 自检**

Run:
- `gob121`

**Step 3: 修复阻断问题**

优先处理语法错误、导入错误和明显的运行时阻断。

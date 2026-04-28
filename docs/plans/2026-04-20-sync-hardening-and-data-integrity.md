# Sync Hardening and Data Integrity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复当前最危险的同步一致性问题，先把离线创建、编辑、删除与重复同步导致的脏数据风险降下来。

**Architecture:** 服务端先补 `client_id` 幂等和 `sync push` 逐条回执；客户端先补队列重写能力，让 pending create 能被后续本地编辑/删除吸收，不再无限追加冲突操作。先做最小闭环，不在这一轮重做编辑器和内容模型。

**Tech Stack:** Go, Gin, PostgreSQL, Flutter, Riverpod, SQLite

---

### Task 1: 服务端 sync 幂等与逐条回执

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `server/internal/repository/store.go`
- Modify: `server/internal/repository/memory.go`
- Modify: `server/internal/repository/postgres.go`
- Modify: `server/internal/service/app.go`
- Test: `server/internal/service/app_test.go`

**Step 1: 写测试**

覆盖：
- 同一 `client_id` 的 `create_card` 重试不会重复建卡
- `create_card` 必须校验 deck 属于当前用户
- `sync push` 返回逐条结果

**Step 2: 扩展模型**

给 `SyncPushResponse` 增加 `results` 数组，元素包含：
- `operation_id`
- `applied`
- `error`

**Step 3: 增加仓储查询**

在仓储接口中补 `GetCardByClientID(userID, clientID)`。

**Step 4: 修改服务层**

- `CreateCard` 先校验 deck
- 若 `client_id` 已存在，直接返回已有卡片
- `SyncPush` 为每个 operation 记录成功/失败结果

**Step 5: 运行测试**

Run: `go test ./...`

---

### Task 2: 客户端队列重写与部分成功清理

**Files:**
- Modify: `client/lib/core/database/local_cache.dart`
- Modify: `client/lib/core/app_store.dart`

**Step 1: 给本地队列增加 replace 能力**

增加 `replaceSyncOperations`，支持整批覆盖。

**Step 2: 让本地编辑吸收 pending create**

若某卡片还没同步成功，但已经存在待同步 `create_card`：
- 编辑时直接改该 `create_card.payload`
- 不再额外排 `update_card`

**Step 3: 让删除本地未同步卡撤销队列**

若删除的是本地未同步卡：
- 删除本地卡
- 删除相关 pending `create/update/review`
- 不再向服务端补发删除

**Step 4: 按服务端 results 清理成功队列**

`syncPendingOperations` 只删除服务端已确认成功的操作，失败项保留。

**Step 5: 运行静态检查**

Run: `flutter analyze`

---

### Task 3: 下一阶段整改

下一轮继续处理：
- 数据库约束 / 索引 / migration 漂移
- `DeleteDeck` 行为一致性
- 本地离线 review 的即时状态更新
- 编辑器与 `content/front/back` 模型收敛

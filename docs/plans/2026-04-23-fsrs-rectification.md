# FSRS Rectification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复项目中 FSRS 调度、学习态状态机、离线复习回放时间与相关测试覆盖问题。

**Architecture:** 先在服务端补针对性失败用例，锁定 interval 计算、learning->review 迁移、离线回放时间与 rating 校验等行为；随后修复 Go 端 FSRS 核心与 service 层 review 时间入口；最后将 Flutter 离线镜像抽到独立调度器，复用同一套规则并补客户端测试，确保在线/离线行为一致。

**Tech Stack:** Go、Flutter/Dart、Gin、Riverpod、go test、flutter test

---

### Task 1: 服务端 FSRS 回归测试

**Files:**
- Modify: `server/internal/pkg/fsrs/algorithm_test.go`
- Modify: `server/internal/service/app_test.go`

**Step 1:** 补 `Review` 用例，覆盖：learning 状态下连续 `Good` 可毕业到 review、review 状态下 `Good` 间隔 > 1 天、非法 rating 被拒绝。

**Step 2:** 补 service 用例，覆盖：`SyncPush submit_review` 使用 `OccurredAt` 而不是服务端当前时间。

**Step 3:** 运行 `go test ./...`，先看失败点是否命中预期。

### Task 2: 服务端算法与 service 修复

**Files:**
- Modify: `server/internal/pkg/fsrs/algorithm.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`

**Step 1:** 修正 forgetting curve / interval factor，确保 retrievability 与 next interval 使用同一套正值因子。

**Step 2:** 修正 learning / relearning 状态机：`Good` 可从 learning 态毕业，`Good`/`Easy` 可从 relearning 态回到 review 态。

**Step 3:** 给 review 增加统一的 rating 校验，并新增按指定 `reviewedAt` 计算的入口，供 sync replay 复用 `OccurredAt`。

**Step 4:** 跑 `go test ./...`，确认全部通过。

### Task 3: 客户端离线 FSRS 镜像重构

**Files:**
- Create: `client/lib/core/fsrs_scheduler.dart`
- Modify: `client/lib/core/app_store.dart`
- Create: `client/test/core/fsrs_scheduler_test.dart`

**Step 1:** 将离线 FSRS 逻辑抽成独立调度器，复用与服务端一致的公式、状态机与 rating 校验。

**Step 2:** 让 `AppStore.submitReview` 调用新调度器，保留现有离线队列流程。

**Step 3:** 补客户端单元测试，覆盖 new/learning/review/relearning 典型路径与非法 rating。

**Step 4:** 运行 `flutter test`。

### Task 4: 全量回归与结果整理

**Files:**
- Modify: `docs/plans/2026-04-23-fsrs-rectification.md`

**Step 1:** 运行 `go test ./...` 与 `flutter test`。

**Step 2:** 在计划文档尾部追加执行结果与已修复风险列表。

---

## Execution Result

- 已修复服务端 FSRS forgetting curve / interval factor，interval 不再退化为固定 1 天。
- 已修复 learning / relearning 状态机，`Good` 可从 learning 态毕业到 review。
- 已新增服务端 review rating 校验，非法 rating 会返回 `invalid review rating`。
- 已修复 sync replay：`submit_review` 现使用 `OccurredAt` 回放，避免离线复习时间漂移。
- 已将 Flutter 离线 FSRS 镜像抽到 `client/lib/core/fsrs_scheduler.dart`，避免继续散落在 `AppStore` 中。
- 已新增 Go / Flutter 回归测试覆盖上述关键路径。

## Verification

- `go test ./...` ✅
- `flutter test` ✅
- `flutter analyze` ✅

# Open Source FSRS Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 用官方开源 FSRS 实现替换项目中手写的 Go / Dart 调度核心，同时保持现有复习队列与产品层行为不变。

**Architecture:** 先锁定当前项目里 FSRS 的接入边界，只替换算法适配层，不动 due queue、每日配额、同步协议等产品逻辑；服务端接 `go-fsrs` 作为真实调度引擎，客户端接 Dart `fsrs` 作为离线镜像，并补跨端一致性测试，确保在线/离线评分结果一致。

**Tech Stack:** Go、Flutter/Dart、go-fsrs、Dart fsrs、go test、flutter test、flutter analyze

---

### Task 1: 依赖与接入边界确认

**Files:**
- Modify: `server/go.mod`
- Modify: `client/pubspec.yaml`
- Modify: `client/pubspec.lock`

**Step 1:** 检查现有服务端 `server/internal/pkg/fsrs/algorithm.go` 与客户端 `client/lib/core/fsrs_scheduler.dart` 的 public API，确认外层只依赖 `Review(state, rating, now)` / `review(current, rating, now)`。

**Step 2:** 服务端加入 `github.com/open-spaced-repetition/go-fsrs/v4` 依赖；客户端加入 `fsrs` 包依赖。

**Step 3:** 拉取依赖并记录官方库当前默认参数、learning/relearning steps、评分与状态枚举。

### Task 2: 服务端替换为官方 go-fsrs 适配层

**Files:**
- Modify: `server/internal/pkg/fsrs/algorithm.go`
- Modify: `server/internal/pkg/fsrs/algorithm_test.go`

**Step 1:** 保留现有 `Engine` / `ReviewRating` / `IsValidReviewRating` 对外接口，内部改为官方 `go-fsrs` 调度。

**Step 2:** 编写项目 `model.FSRSState` 与官方 `fsrs.Card` 的双向映射，确保 `state/difficulty/stability/due_date/last_review_at/reps/lapses/elapsed_days/scheduled_days` 正确转换。

**Step 3:** 用官方结果重写/补充测试，覆盖 new / learning / review / relearning 典型路径。

**Step 4:** 运行 `go test ./...`，确认 service 层无回归。

### Task 3: 客户端替换为官方 Dart fsrs 适配层

**Files:**
- Modify: `client/lib/core/fsrs_scheduler.dart`
- Modify: `client/test/core/fsrs_scheduler_test.dart`
- Modify: `client/lib/core/app_store.dart`（仅在需要适配字段时）

**Step 1:** 保留现有 `FsrsScheduler` / `FsrsState` / `ReviewRating` 对外接口，内部改为 Dart `fsrs` 适配器。

**Step 2:** 统一时区处理为 UTC 计算，输出时再回到应用当前 `DateTime` 表达，避免 Dart fsrs 的 UTC-only 约束导致离线结果偏差。

**Step 3:** 校准字段映射，确保服务端返回状态与客户端离线状态可互相读写。

**Step 4:** 运行 `flutter test` 与 `flutter analyze`。

### Task 4: 跨端一致性回归

**Files:**
- Create: `client/test/core/fsrs_cross_platform_contract_test.dart`（如需要）
- Modify: `docs/plans/2026-04-29-open-source-fsrs-integration.md`

**Step 1:** 选一组固定初始状态与评分序列，验证服务端与客户端输出的 `state / due_date / difficulty / stability / lapses / reps` 一致或误差在可解释范围内。

**Step 2:** 记录最终差异、兼容策略与剩余风险。


## Execution Result

- 服务端已接入 `github.com/open-spaced-repetition/go-fsrs/v4`，`server/internal/pkg/fsrs/algorithm.go` 现为官方库适配层，不再使用项目内手写 19 权重实现。
- 客户端离线调度已重写为对齐官方 `go-fsrs v4` 的 Dart 适配层，避免继续使用旧的手写镜像公式。
- 已补充官方基准序列测试，验证 `Good, Good, Good, Good, Good, Good, Again, Again, Good, Good, Good, Good, Good` 的状态与间隔序列与官方实现一致。
- `retrievability` 已改为存储“到下次到期时的预测记忆率”，并保留分钟级学习步的分数精度。
- 为接入 `go-fsrs/v4`，服务端 `go.mod` 已升级到 `go 1.26`。

## Verification

- `cd server && go test ./...` ✅
- `cd client && flutter test -r compact` ✅
- `cd client && flutter analyze` ✅

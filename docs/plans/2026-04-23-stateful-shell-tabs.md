# Stateful Bottom Tabs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把当前 4 个独立页面式底部导航改成固定主框架 + 保活 tab 内容区，消除整屏跳转感。

**Architecture:** 使用 `go_router` 的 `StatefulShellRoute.indexedStack` 承载 4 个主 tab。Shell 层统一管理底部导航与鉴权态，4 个分支分别维护自己的导航栈；牌组详情、卡片编辑、DSL 导入等二级页面继续挂在对应 branch 下。

**Tech Stack:** Flutter, go_router 14, flutter_riverpod, Material 3 NavigationBar

---

### Task 1: 重构路由为 stateful shell

**Files:**
- Modify: `client/lib/app/router.dart`
- Modify: `client/lib/app/screens.dart`

**Step 1: 写出 shell 结构**
- 在 `router.dart` 中把现有单层 `GoRoute` 改为 `StatefulShellRoute.indexedStack`
- 建立 4 个 branch：`/`、`/review`、`/stats`、`/settings`

**Step 2: 把二级页面挂到对应 branch**
- 牌组详情、卡片新增/编辑、DSL 导入挂到牌组 branch
- 保持现有绝对路径不变：`/deck/:deckId`、`/deck/:deckId/add-card`、`/deck/:deckId/card/:cardId/edit`、`/import/dsl`

**Step 3: 在 screens 中实现统一 shell**
- 新增统一的 shell scaffold
- 由 shell 统一渲染底部导航，并按主 tab location 决定是否显示
- shell 负责 bootstrapping / 未登录态兜底

**Step 4: 精简页面内重复的底部导航**
- 从 Deck / Review / Stats / Settings 四个主页面里移除原本的 `bottomNavigationBar`
- 保留各页面现有 `Scaffold`、`AppBar` 与业务内容

### Task 2: 适配 tab 切换行为

**Files:**
- Modify: `client/lib/app/screens.dart`

**Step 1: 改造 `_AppBottomNav`**
- 改为接收 `currentIndex` 与 `onDestinationSelected`
- 点击 tab 时调用 `navigationShell.goBranch(...)`

**Step 2: 保留 branch 状态**
- 不同 tab 切换时恢复各自 branch 的最后位置
- 重复点击当前 tab 时回到该 branch 初始页面

### Task 3: 回归验证

**Files:**
- Test: `client/lib/app/router.dart`
- Test: `client/lib/app/screens.dart`

**Step 1: 静态检查**
Run: `flutter analyze`
Expected: PASS

**Step 2: 自动化测试**
Run: `flutter test`
Expected: PASS

**Step 3: 手动体验验证**
- 在 iOS 模拟器中切换 4 个 tab
- 确认底部导航不再整屏重建，且切回 tab 时内容状态保留

# Review Controls, Highlight Toolbar, and Folder Hierarchy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add editor highlight support, fix inline font size toggle behavior, make cards opt-in for review with sequential/random deck review order, and introduce folders above decks.

**Architecture:** Keep the editor changes local to the Flutter client by reusing the existing inline-style model/DSL codec and adding a deterministic span-application helper. For review controls and folders, extend the shared domain model on both Flutter and Go, persist new fields in PostgreSQL/local cache, and update the home/deck flows so the UI matches the new data model end-to-end.

**Tech Stack:** Flutter + Riverpod + sqflite, Go + Gin + PostgreSQL, existing sync/local-cache pipeline, Flutter/widget tests and Go unit tests.

---

### Task 1: Add an explicit implementation seam for inline styles

**Files:**
- Modify: `client/lib/app/editor/rich_text_controller.dart`
- Test: `client/test/editor/inline_style_application_test.dart`

**Step 1: Write the failing tests**
- Add tests for:
  - applying `InlineStyle.highlight` to a range;
  - applying `fontLarge` then `fontSmall` to the same range;
  - applying `fontSmall` then `fontLarge` to the same range;
  - toggling the same style off on the same range.

**Step 2: Run test to verify it fails**
Run: `flutter test client/test/editor/inline_style_application_test.dart`
Expected: FAIL because there is no reusable span-update helper and font-size replacement is not deterministic.

**Step 3: Write minimal implementation**
- Introduce a public helper in `rich_text_controller.dart` that updates spans for a selected range.
- Treat `fontSmall` and `fontLarge` as mutually exclusive.
- Remove/split overlapping spans of the same style family before adding the new span.
- Sort style application deterministically when building text styles.

**Step 4: Run test to verify it passes**
Run: `flutter test client/test/editor/inline_style_application_test.dart`
Expected: PASS.

### Task 2: Expose the highlight tool in the editor UI

**Files:**
- Modify: `client/lib/app/editor/card_editor_screen.dart`
- Test: `client/test/editor/card_editor_screen_test.dart`

**Step 1: Write the failing test**
- Extend the card editor widget test to expect a toolbar button labeled `高亮` or `荧光笔` on phone-sized viewports.

**Step 2: Run test to verify it fails**
Run: `flutter test client/test/editor/card_editor_screen_test.dart`
Expected: FAIL because the toolbar currently exposes bold/underline/font controls only.

**Step 3: Write minimal implementation**
- Add a toolbar action for highlight.
- Route it through the new inline-style helper.
- Keep the existing WYSIWYG flow and preview/DSL encoding intact.

**Step 4: Run test to verify it passes**
Run: `flutter test client/test/editor/card_editor_screen_test.dart`
Expected: PASS.

### Task 3: Extend shared models for folders, review order, and opt-in review cards

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `server/internal/repository/store.go`
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/core/network/api_client.dart`
- Modify: `client/lib/core/database/local_cache.dart`
- Modify: `server/migrations/001_init.up.sql` only if needed for fresh schema parity
- Create: `server/migrations/002_review_controls_and_folders.up.sql`
- Create: `server/migrations/002_review_controls_and_folders.down.sql`

**Step 1: Write the failing tests**
- Add Go tests for folder CRUD / folder delete unassigning decks / due queue excluding cards not in review.
- Add Flutter review-queue tests for `studyEnabled == false` exclusion and random order behavior for deck review.

**Step 2: Run tests to verify they fail**
Run: `go test ./...`
Run: `flutter test client/test/core/review_queue_test.dart`
Expected: FAIL because models and queue logic do not yet know about folders, review order, or review opt-in.

**Step 3: Write minimal implementation**
- Add `Folder` model plus folder CRUD store methods.
- Add `folder_id` and `review_order` to decks.
- Add `study_enabled` to cards.
- Bump local cache schema version and add a `folders` table.
- Extend sync pull payloads and client bootstrap/refresh paths to read/write folders.

**Step 4: Run tests to verify they pass**
Run: `go test ./...`
Run: `flutter test client/test/core/review_queue_test.dart`
Expected: PASS.

### Task 4: Implement service/repository/handler behavior end-to-end

**Files:**
- Modify: `server/internal/repository/memory.go`
- Modify: `server/internal/repository/postgres.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/handler/http.go`
- Modify: `server/api/openapi.yaml`
- Test: `server/internal/service/app_test.go`
- Test: `server/internal/repository/memory_test.go`

**Step 1: Write the failing tests**
- Cover:
  - cards with `study_enabled=false` not appearing in due cards;
  - deck review order remaining sequential by default;
  - `review_order=random` shuffling deck-specific review queue;
  - folder deletion unassigning deck `folder_id` instead of deleting decks.

**Step 2: Run test to verify it fails**
Run: `go test ./server/internal/...`
Expected: FAIL because the repository schema and handlers do not expose the new behavior.

**Step 3: Write minimal implementation**
- Add folder endpoints.
- Update deck/card insert/select/update SQL and memory-store logic.
- Filter due-card queries by `study_enabled=true`.
- Validate folder ownership in deck create/update.
- Keep default deck creation compatible with the new fields.

**Step 4: Run test to verify it passes**
Run: `go test ./server/internal/...`
Expected: PASS.

### Task 5: Update Flutter state/actions and deck/card UI

**Files:**
- Modify: `client/lib/core/app_store.dart`
- Modify: `client/lib/app/screens.dart`
- Modify: `client/lib/app/editor/card_editor_screen.dart`
- Possibly modify: `client/lib/app/router.dart` if navigation hooks are needed
- Test: `client/test/editor/card_editor_route_test.dart`
- Test: `client/test/editor/card_editor_screen_test.dart`
- Test: `client/test/core/review_queue_test.dart`

**Step 1: Write the failing tests**
- Add/extend tests for:
  - editor create/edit initializes and saves `studyEnabled`;
  - deck review queue ignores cards not opted into review;
  - random review order does not break queue sizing;
  - home screen can render folder-grouped decks without throwing.

**Step 2: Run test to verify it fails**
Run: `flutter test`
Expected: FAIL because UI/state do not yet expose the new fields or grouped layout.

**Step 3: Write minimal implementation**
- Add folder CRUD methods to `AppStore`.
- Add deck create/edit controls for folder selection and review order.
- Add card-level review toggle in editor + deck list item.
- Group home-screen decks by folder, keep an "未分类" section, and add folder create/edit/delete sheets.

**Step 4: Run test to verify it passes**
Run: `flutter test`
Expected: PASS.

### Task 6: Final verification and cleanup

**Files:**
- Review all changed files

**Step 1: Run formatters**
Run: `dart format client/lib client/test`
Run: `gofmt -w server/internal server/cmd`
Expected: all files formatted.

**Step 2: Run full verification**
Run: `flutter test`
Run: `go test ./...`
Expected: PASS.

**Step 3: Smoke-check critical UX flows**
- Create folder
- Create deck under folder with sequential/random mode
- Create card with review disabled
- Toggle card into review and confirm due count changes
- Verify highlight button and font up/down behavior in editor preview/save cycle

**Step 4: Commit**
```bash
git add client server docs/plans/2026-04-29-review-controls-and-folders.md
git commit -m "feat: add review controls and deck folders"
```

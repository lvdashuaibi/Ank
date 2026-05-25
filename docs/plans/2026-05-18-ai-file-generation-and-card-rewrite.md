# AI File Generation And Card Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build first-phase AI card creation from PDF/TXT/MD files and add AI-assisted card rewriting for existing cards.

**Architecture:** Keep AI orchestration on the Go server so every client uses the same parsing, prompting, and Card DSL output. The Flutter client only selects files, sends generation/rewrite requests, previews returned drafts, and lets the user explicitly save or apply changes.

**Tech Stack:** Flutter, Riverpod, Dio multipart uploads, Go/Gin, OpenAI-compatible chat completions, Card DSL, server-side FSRS scheduling.

---

### Task 1: Extend AI Models

**Files:**
- Modify: `server/internal/model/model.go`
- Modify: `client/lib/core/app_store.dart`

**Steps:**
1. Add document metadata, generated card type/source fields, file generation request metadata, and rewrite request/response structs.
2. Preserve backward compatibility with existing `front`/`back` generated-card responses.
3. Run `go test ./...` and `flutter analyze`.

### Task 2: Add Server File Text Extraction

**Files:**
- Create: `server/internal/service/document_text.go`
- Test: `server/internal/service/document_text_test.go`

**Steps:**
1. Implement TXT/MD UTF-8 extraction.
2. Implement best-effort text PDF extraction for selectable-text PDFs without OCR.
3. Return a clear error when the file is empty, too large, unsupported, or a scanned PDF yields no text.
4. Run `go test ./internal/service`.

### Task 3: Add AI File Generation Endpoint

**Files:**
- Modify: `server/internal/handler/http.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/service/ai_provider.go`
- Modify: `server/api/openapi.yaml`

**Steps:**
1. Add `POST /api/v1/ai/import-file` multipart endpoint.
2. Parse `file`, `topic`, `card_count`, `difficulty`, and `card_types`.
3. Extract document text, call the same generation pipeline with FSRS-friendly prompt rules, and return generated drafts plus document metadata.
4. Run server tests.

### Task 4: Add AI Card Rewrite Endpoint

**Files:**
- Modify: `server/internal/handler/http.go`
- Modify: `server/internal/service/app.go`
- Modify: `server/internal/service/ai_provider.go`
- Modify: `server/api/openapi.yaml`

**Steps:**
1. Add `POST /api/v1/ai/rewrite-card`.
2. Support rewrite types: improve wording, simplify answer, make cloze, make choice, split.
3. Return one or more candidate Card DSL drafts with change summaries.
4. Run server tests.

### Task 5: Add Client API And Store Methods

**Files:**
- Modify: `client/lib/core/network/api_client.dart`
- Modify: `client/lib/core/app_store.dart`

**Steps:**
1. Add multipart `generateCardsFromFile`.
2. Add JSON `rewriteCardWithAI`.
3. Store generated file drafts in the existing generated-card state and expose rewrite candidates.
4. Run `flutter analyze`.

### Task 6: Upgrade AI Generation UI

**Files:**
- Modify: `client/lib/app/screens.dart`

**Steps:**
1. Add a source mode selector: topic/context or file.
2. Allow picking `.pdf`, `.txt`, `.md`.
3. Show selected filename and document preview metadata after generation.
4. Preserve save-to-review behavior.
5. Run Flutter widget tests.

### Task 7: Add AI Rewrite UI In Card Editor

**Files:**
- Modify: `client/lib/app/editor/card_editor_screen.dart`

**Steps:**
1. Add an `AI 优化` action for existing cards.
2. Show rewrite presets and custom instruction.
3. Preview returned candidates and apply selected candidate to the editor.
4. Run editor tests.

### Task 8: Full Verification

**Files:**
- Test: `server/internal/service/*_test.go`
- Test: `client/test/**`

**Steps:**
1. Run `cd server && go test ./...`.
2. Run `cd client && flutter analyze`.
3. Run `cd client && flutter test -r compact`.
4. If simulator is available, launch with the existing API base URL and manually verify the new entry points.

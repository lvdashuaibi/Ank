# Card DSL Import Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Card DSL import behavior match the current project implementation more closely, with safer parsing, clearer validation, and UI guidance that reflects the syntax users can actually use today.

**Architecture:** Keep the existing two-layer model: the outer import parser extracts card blocks and metadata, while the existing body DSL parser continues to render front/back content. Improve the outer parser to support both wrapped and simplified inputs, trim structural tokens correctly, and return actionable parse errors. Then update the import screen copy/sample to describe the real supported input forms and add parser tests around the new behavior.

**Tech Stack:** Flutter, Dart, flutter_test

---

### Task 1: Harden outer Card DSL parsing

**Files:**
- Modify: `client/lib/core/import/card_dsl_parser.dart`
- Test: `client/test/import/card_dsl_parser_test.dart`

**Step 1:** Write failing tests for wrapped blocks, simplified blocks, `===` splitting, Chinese comma tag splitting, and `@end` not leaking into back/meta.

**Step 2:** Run the targeted parser tests and verify failure.

**Step 3:** Replace the regex-only block extraction with line-based extraction that supports current real inputs and better diagnostics.

**Step 4:** Run the targeted parser tests and verify pass.

### Task 2: Align import UI with real supported syntax

**Files:**
- Modify: `client/lib/app/card_dsl_import_screen.dart`

**Step 1:** Update sample DSL to show the recommended current format.

**Step 2:** Update copy in the screen to explain wrapped vs simplified import, `===` separators, and actual supported headers.

**Step 3:** Show preview tips/errors in wording that matches the parser behavior.

### Task 3: Validate end-to-end behavior

**Files:**
- Test: `client/test/import/card_dsl_parser_test.dart`

**Step 1:** Run targeted tests for import parser.

**Step 2:** Run related DSL/editor tests to ensure no regression.

**Step 3:** Summarize the new import contract in the final response.

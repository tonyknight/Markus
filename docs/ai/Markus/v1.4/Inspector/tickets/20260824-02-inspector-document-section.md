---
id: 20260824-02-inspector-document-section
title: Inspector Document section
type: feature
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: Filename, kind, UTF-8, line count
parent:
depends_on:
- 20260824-01-inspector-chrome-trailing-pane
subtasks:
- id: T01
  title: Document metadata and kind controls
  status: done
plan_status: done
current_task: T01
---
## Description

Fill the Document section: filename (or Untitled), current `DocumentKind`, UTF-8, line count. Kind picker and Pin/Unpin call existing `DocumentHost` APIs.

## Acceptance criteria

- [x] Filename reflects the open file or Untitled.
- [x] Kind picker lists `DocumentKind.shipped` and calls `setKind`.
- [x] Pin/Unpin match v1.3 (pin needs a file URL; unpin disabled when not pinned).
- [x] Line count is derived from the buffer; encoding label is UTF-8.
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Depends on chrome ticket. Reuse `host.setKind` / `pinKind` / `unpinKind` / `session.isKindPinned`. Do not invent a second kind store.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 Document metadata and kind controls.

## Implementation plan

Status: approved
Current task: T01

### T01: Document metadata and kind controls

Replace the Document placeholder in `InspectorPane`. Line count: split on newlines of `host.session.editor.string` (or existing source-map if cheap). Do not persist encoding.

Files: `Markus/Markus/Inspector/InspectorPane.swift`, possibly a `InspectorDocumentSection.swift`

Verify: same three `xcodebuild` Debug builds as ticket 01.
- [x] done

## Notes

- 2026-08-24: Ticket created. Depends on 01.
- 2026-08-24: Document section shows name, kind picker, Pin/Unpin, UTF-8, line count. Debug builds succeeded.

## Review

- Date: 2026-08-24
- Verdict: Minors only
- Findings:
  - Document section uses `setKind` / `pinKind` / `unpinKind` and `DocumentKind.shipped`. Pin disabled without a file URL.
  - Kind picker hides its label visually (`.labelsHidden()`) but keeps an accessibility label.

---
id: 20260824-02-inspector-document-section
title: Inspector Document section
type: feature
priority: high
status: todo
created: 2026-08-24
updated: 2026-08-24
closed:
notes: Filename, kind, UTF-8, line count
parent:
depends_on:
- 20260824-01-inspector-chrome-trailing-pane
subtasks:
- id: T01
  title: Document metadata and kind controls
  status: todo
plan_status: approved
current_task: T01
---
## Description

Fill the Document section: filename (or Untitled), current `DocumentKind`, UTF-8, line count. Kind picker and Pin/Unpin call existing `DocumentHost` APIs.

## Acceptance criteria

- [ ] Filename reflects the open file or Untitled.
- [ ] Kind picker lists `DocumentKind.shipped` and calls `setKind`.
- [ ] Pin/Unpin match v1.3 (pin needs a file URL; unpin disabled when not pinned).
- [ ] Line count is derived from the buffer; encoding label is UTF-8.
- [ ] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Depends on chrome ticket. Reuse `host.setKind` / `pinKind` / `unpinKind` / `session.isKindPinned`. Do not invent a second kind store.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [ ] T01 Document metadata and kind controls.

## Implementation plan

Status: approved
Current task: T01

### T01: Document metadata and kind controls

Replace the Document placeholder in `InspectorPane`. Line count: split on newlines of `host.session.editor.string` (or existing source-map if cheap). Do not persist encoding.

Files: `Markus/Markus/Inspector/InspectorPane.swift`, possibly a `InspectorDocumentSection.swift`

Verify: same three `xcodebuild` Debug builds as ticket 01.
- [ ] done

## Notes

- 2026-08-24: Ticket created. Depends on 01.

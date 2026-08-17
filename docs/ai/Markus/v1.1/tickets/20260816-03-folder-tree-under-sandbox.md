---
id: 20260816-03-folder-tree-under-sandbox
title: "Folder tree under sandbox"
type: bug
priority: medium
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on: []
subtasks:
  - id: T1
    title: Replace path-based enumeration with security-scoped URL enumeration
    status: todo
  - id: T2
    title: Filter to Markdown extensions, exclude dotfiles, recurse nested folders
    status: todo
  - id: T3
    title: Regression test against a sandboxed fixture folder
    status: todo
---

## Description

Selecting a folder yields an empty library panel. `MarkdownFolderTree.
children(of:)` enumerates with the path-based `contentsOfDirectory
(atPath:)`, which the App Sandbox (`Markus.entitlements`) denies.
Enumeration must go through the security-scoped URL instead. This is the
underlying data fix that ticket 05 (Ribbon rail and library panel)
depends on to have anything to show.

## Acceptance criteria

- [ ] `MarkdownFolderTree.children(of:)` enumerates via the
      security-scoped **URL**, never a path (N7).
- [ ] Opening a folder lists its Markdown files (`.md`, `.markdown`,
      `.mdown`, `.mkd`), including nested folders, excluding dotfiles and
      other file types (R6, population half).
- [ ] A test exercises enumeration against a sandboxed fixture folder and
      would fail if enumeration silently returned empty (N9).

## Context

- Requirements: R6 (population half), N7.
- Planning doc `(2026-08-16) v1.1.md`: D.11.
- Ticket 05 (Ribbon rail and library panel) depends on this ticket —
  the library panel is this tree, relocated.

## Subtasks

- [ ] Replace `contentsOfDirectory(atPath:)` with URL-based enumeration
      that honors the folder's security scope.
- [ ] Apply the Markdown-extension and dotfile filters; recurse into
      nested folders.
- [ ] Add a fixture-backed regression test asserting non-empty, correctly
      filtered results under sandbox conditions.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

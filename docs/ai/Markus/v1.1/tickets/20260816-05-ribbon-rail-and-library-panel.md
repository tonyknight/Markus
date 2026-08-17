---
id: 20260816-05-ribbon-rail-and-library-panel
title: "Ribbon rail and library panel"
type: feature
priority: medium
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on:
  - 20260816-03-folder-tree-under-sandbox
subtasks:
  - id: T1
    title: Build ribbon rail SwiftUI column (hamburger top, gear bottom)
    status: todo
  - id: T2
    title: Library panel closed-by-default / hamburger-toggle logic
    status: todo
  - id: T3
    title: Empty state offering Open Folder… with no folder session
    status: todo
---

## Description

Today's chrome has no consistent home for the folder tree or settings.
This ticket adds a slim vertical ribbon rail pinned to the left of the
document — a hamburger at the top toggling the library panel (the
folder tree, relocated, from ticket 03) and a gear at the bottom opening
settings (ticket 06). With a single file open, the library starts
closed; since opening one file only grants a security scope for that
file (its parent folder cannot be enumerated), pressing the hamburger
with no folder in the session must offer **Open Folder…**, not silently
do nothing.

## Acceptance criteria

- [ ] A left ribbon rail shows a hamburger icon (top) and a gear icon
      (bottom) (R5).
- [ ] The hamburger toggles the library panel open/closed (R5).
- [ ] The library panel shows the filtered Markdown hierarchy from
      ticket 03 (R6).
- [ ] With a single file open, the library starts **closed**; it opens
      only via the hamburger or Open Folder (R6).
- [ ] Pressing the hamburger with no folder session presents an empty
      state offering **Open Folder…**, not a blank panel (R6).

## Context

- Requirements: R5, R6 (toggle/closed-by-default/empty-state half).
- Planning doc `(2026-08-16) v1.1.md`: B.6, B.7.
- Depends on ticket 03 — the library panel *is* the folder tree, and
  needs it populating correctly first.
- The gear button is wired to open settings, built out in ticket 06.

## Subtasks

- [ ] Build the ribbon rail SwiftUI column.
- [ ] Wire the hamburger to toggle the library panel; implement
      closed-by-default when only a single file is open.
- [ ] Implement the empty state (offering Open Folder…) for the
      no-folder-session case.
- [ ] Wire the gear button to present the settings surface (stub is fine
      until ticket 06 lands; final integration happens there).

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

---
id: 20260816-06-settings-surface
title: "Settings surface"
type: feature
priority: medium
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on:
  - 20260816-05-ribbon-rail-and-library-panel
subtasks:
  - id: T1
    title: Full-viewport settings scene (category list + detail panel)
    status: todo
  - id: T2
    title: Working close box, not nested in another NavigationStack
    status: todo
  - id: T3
    title: Remove the old side-panel settings and its dead Done button
    status: todo
---

## Description

Today's settings side panel cannot be dismissed because its Done button
is hoisted out of a nested `NavigationStack` into the window toolbar.
This ticket replaces it with a proper full-viewport settings surface —
a category list on the left, the active setting on the right, and a
working close box — reachable from the ribbon rail's gear (ticket 05).

## Acceptance criteria

- [ ] Settings fill the viewport: a category list on the left, the
      active setting on the right, and a working close box (R7).
- [ ] Settings are not a sheet, not a side pane, and not nested inside
      another `NavigationStack` (R7; Component 5).
- [ ] The gear button in the ribbon rail opens this surface.
- [ ] The old side-panel implementation and its unreachable Done button
      are removed.

## Context

- Requirements: R7; Architecture component 5 "Settings surface".
- Planning doc `(2026-08-16) v1.1.md`: B.8.
- Depends on ticket 05 for the ribbon rail gear entry point.
- Ticket 07 (Theme proxy and global theme) builds the themes category
  that lives inside this surface — sequenced after this ticket lands
  the surface itself.

## Subtasks

- [ ] Build the full-viewport settings scene: category list, detail
      panel.
- [ ] Implement the close box and confirm it actually dismisses (root
      cause of the old bug was NavigationStack nesting — do not repeat
      it).
- [ ] Wire the gear button (ticket 05) to present this surface.
- [ ] Remove the old side-panel settings implementation.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

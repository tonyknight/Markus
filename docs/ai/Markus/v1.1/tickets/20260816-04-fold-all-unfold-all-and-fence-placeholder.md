---
id: 20260816-04-fold-all-unfold-all-and-fence-placeholder
title: "Fold All / Unfold All and fence placeholder"
type: feature
priority: high
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on:
  - 20260816-02-window-geometry-and-appkit-main-menu
subtasks:
  - id: T1
    title: Fold-all / unfold-all traversal over the block index
    status: todo
  - id: T2
    title: Wire Edit menu items (from ticket 02) to the fold service
    status: todo
  - id: T3
    title: Fence placeholder — opening fence line plus short placeholder
    status: todo
---

## Description

Fold All / Unfold All is named in v1's planning file, in v1's R4, and in
both of v1's acceptance-criteria lists, but no code implements it — the
v1 completion note claiming it shipped was wrong. Separately, a folded
fenced block simply vanishes today instead of showing "the opening fence
and a short placeholder" as v1 specified. This ticket delivers both,
wired to the Edit menu items ticket 02 creates.

## Acceptance criteria

- [ ] Fold All collapses every foldable block in the document; Unfold
      All restores them (R14).
- [ ] Both are reachable from the Edit menu built in ticket 02 (R14).
- [ ] A folded fence shows its opening fence line plus a short
      placeholder, not an empty gap (R15).
- [ ] Folding stays a layout concern: zero-height owned fragments; the
      buffer is never rewritten and paragraph styles are never collapsed
      to hide text (N3).
- [ ] Tests assert live fold state (blocks actually collapsed/restored),
      not a flag that can't fail (N9).

## Context

- Requirements: R14, R15, N3.
- Planning doc `(2026-08-16) v1.1.md`: F.15, F.16; background item 3
  ("Fold all / unfold all does not exist").
- Depends on ticket 02 for the Edit menu items that trigger these
  actions.
- Feeds ticket 12 (Fold persistence and repair), which needs a working
  fold service to persist and repair.

## Subtasks

- [ ] Implement fold-all / unfold-all traversal over the block index.
- [ ] Wire the Edit menu's Fold All / Unfold All items (added in ticket
      02, currently targeting `nil` with no handler) to this service.
- [ ] Render the fence placeholder (opening fence line + short
      placeholder text) for a folded fenced block.
- [ ] Tests: fold-all collapses every foldable block; unfold-all restores
      them; a folded fence shows the placeholder, not nothing.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

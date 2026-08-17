---
id: 20260816-12-fold-persistence-and-repair
title: "Fold persistence and repair"
type: feature
priority: medium
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on:
  - 20260816-04-fold-all-unfold-all-and-fence-placeholder
subtasks:
  - id: T1
    title: Add FoldID.anchor (short digest of the block's opening line)
    status: todo
  - id: T2
    title: Persist fold set per file in app storage
    status: todo
  - id: T3
    title: Repair fold IDs against anchors when the block index rebuilds
    status: todo
---

## Description

`FoldID` is `kind + startLine`, and rebuilding the block index after an
edit leaves folds pointing at stale line numbers; v1 called for repair
on rebuild and there is none. Separately, `FoldStore` is an in-memory
`Set` and nothing is written — v1 specified per-file persistence in app
state. This ticket lands **before** editing (ticket 13) deliberately:
editing is what breaks stale fold IDs, so repair has to exist before
typing does.

## Acceptance criteria

- [ ] Folds persist per file across relaunch, in app storage — not an
      in-memory `Set` (R16).
- [ ] `FoldID` gains an `anchor` (short digest of the block's opening
      line) (Data model `FoldID`).
- [ ] When the block index is rebuilt after an edit, fold IDs are
      repaired against their anchors rather than left pointing at stale
      line numbers (R17).
- [ ] A fold survives an edit made elsewhere in the document (R17).

## Context

- Requirements: R16, R17; Data model `FoldID.anchor`; Constraints
  ("Files remain the source of truth... Folds... live in app storage").
- Planning doc `(2026-08-16) v1.1.md`: F.17, F.18.
- Depends on ticket 04 for the fold service this persists and repairs.
- Ticket 13 (Text input in Source) depends on this ticket — per the
  Requirements Tasks Breakdown, this "lands before editing because
  editing is what breaks stale IDs."

## Subtasks

- [ ] Add `anchor: String` to `FoldID`, computed as a short digest of the
      block's opening line.
- [ ] Implement per-file fold persistence (app storage, e.g.
      `UserDefaults` keyed by file).
- [ ] Implement repair: on block-index rebuild, match existing fold
      anchors against the new index and update `startLine` accordingly.
- [ ] Test: fold a block, edit elsewhere in the document, confirm the
      fold survives; relaunch, confirm folds are restored.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

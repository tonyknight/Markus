---
id: 20260816-09-preview-gutter-and-source-mapping
title: Preview gutter and source mapping
type: feature
priority: medium
status: in-progress
created: 2026-08-16
updated: 2026-08-18
closed:
notes: ''
parent:
depends_on:
- 20260816-08-preview-rendering-via-paragraph-substitution
subtasks:
- id: T1
  title: Block-anchored gutter renderer for Preview (chevrons + block-start numbers)
  status: todo
- id: T2
  title: Source-line anchor carried per substituted paragraph
  status: todo
- id: T3
  title: Reconcile go-to-line, outline jump, and minimap against block anchors
  status: todo
---
## Description

Once a rendered paragraph no longer occupies the same number of visual
lines as its source, per-line numbering in Preview is a fiction. This
ticket revises the gutter: Source keeps a number for every source line;
Preview instead shows fold chevrons for every foldable block plus a
source line number at each rendered block's start. This is a **revision
of v1's R6**.

## Acceptance criteria

- [ ] Source shows a line number for every source line (unchanged
      behaviour) (R13).
- [ ] Preview shows fold chevrons for every foldable block, plus a source
      line number at each rendered block's start (R13).
- [ ] Go-to-line, outline jump, and the minimap all agree with both
      gutter modes (R13).

## Context

- Requirements: R13 (revises v1 R6).
- Planning doc `(2026-08-16) v1.1.md`: "Recommended direction" →
  "Preview gutter: block-anchored numbers" for the full rationale.
- Depends on ticket 08 — block-anchored numbering needs substituted
  paragraphs (and their source element ranges) to anchor to.
- Every substituted paragraph in ticket 08 already carries its source
  element range (per the "Rendered Preview" rationale) — this ticket
  consumes that, it doesn't add it.

## Subtasks

- [ ] Implement the block-anchored gutter renderer for Preview mode
      (chevron per foldable block, number at each rendered block's
      start).
- [ ] Confirm each substituted paragraph exposes its source-line anchor
      to the gutter.
- [ ] Update go-to-line, outline jump, and minimap click-to-scroll to
      resolve against block anchors in Preview mode.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

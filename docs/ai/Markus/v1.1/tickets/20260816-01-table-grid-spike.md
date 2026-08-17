---
id: 20260816-01-table-grid-spike
title: "Table grid spike"
type: spike
priority: high
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: "Hard gate: sequenced first, decides whether ticket 08 can proceed as designed."
parent:
depends_on: []
subtasks:
  - id: T1
    title: Prototype NSTextAttachment sizing/measurement from column content
    status: todo
  - id: T2
    title: Draw aligned grid (borders, column widths) in the attachment cell
    status: todo
  - id: T3
    title: Attach full table source-range metadata to the attachment
    status: todo
  - id: T4
    title: Validate selection over the attachment can resolve to source range
    status: todo
  - id: T5
    title: Go/no-go call; if impractical, stop and reopen design
    status: todo
---

## Description

A GFM table is one cmark node spanning several source lines, but the
paragraph-substitution approach chosen for Preview rendering (see
Requirements Architecture, "Preview rendering") is per-paragraph. A table
therefore needs a custom-drawn `NSTextAttachment` that measures column
widths and draws a true grid. This is the release's single largest
technical unknown and is sequenced first as a **hard gate**: ticket 08
(Preview rendering) depends on it, and if a true grid proves impractical
on this stack, the correct response is to stop and reopen design — not to
degrade silently to a styled-but-misaligned table.

## Acceptance criteria

- [ ] An `NSTextAttachment` subtype measures column widths from cell
      content and draws an aligned grid (R11).
- [ ] The attachment carries the table's full source byte range so a
      later selection over it can resolve back to source Markdown (feeds
      R22 in ticket 13).
- [ ] The attachment composes with folding: it behaves as a normal owned
      layout element and does not break `FoldingTextLayoutFragment`
      folding of surrounding content (N3).
- [ ] **Hard gate documented:** a clear go/no-go decision is recorded on
      this ticket. If no-go, this ticket stops here and reopens
      architecture discussion rather than shipping a degraded table.

## Context

- Requirements: R11, N4, Architecture component 8 "Table attachment",
  Data model `TableLayout`.
- Planning doc `(2026-08-16) v1.1.md`: "Recommended direction" →
  "Rendered Preview: paragraph substitution, one buffer", point 1
  ("Tables are a true grid (decided)"); Risks and assumptions, "The
  table grid is the main risk."
- This ticket produces the attachment type that ticket 08 integrates
  into the `NSTextContentStorageDelegate` substitution path.

## Subtasks

Detailed checklist (mirrors frontmatter `subtasks`):

- [ ] Prototype attachment sizing/measurement from parsed GFM table cell
      content (columns, alignment).
- [ ] Draw the grid: borders, aligned columns, per-cell text.
- [ ] Carry the table's full source `Range<Int>` on the attachment
      (`TableLayout.sourceRange`).
- [ ] Validate that a selection spanning the attachment can be resolved
      back to that source range (needed for R22 later).
- [ ] Record the go/no-go decision and rationale in Notes.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

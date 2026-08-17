---
id: 20260816-08-preview-rendering-via-paragraph-substitution
title: "Preview rendering via paragraph substitution"
type: feature
priority: high
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on:
  - 20260816-01-table-grid-spike
subtasks:
  - id: T1
    title: Implement NSTextContentStorageDelegate substitution path
    status: todo
  - id: T2
    title: Full GFM span coverage (emphasis, strong, quotes, lists, breaks, links)
    status: todo
  - id: T3
    title: Integrate table attachment from ticket 01
    status: todo
  - id: T4
    title: Degrade images to readable styled text, not raw syntax
    status: todo
  - id: T5
    title: Fixtures/assertions that exercise what a reader actually sees
    status: todo
---

## Description

Preview today only adds attributes to the untouched buffer, so a reader
sees `##`, pipe-and-dash table rules, `- [ ]`, `[text](url)`, and fence
backticks — colourised source, not rendered Markdown. The parser walk
emits no spans at all for emphasis, strong, block quotes, lists, images,
or thematic breaks, and heading level is ignored (every heading is
22pt). This ticket implements the chosen fix: an
`NSTextContentStorageDelegate` that substitutes a rendered
`NSTextParagraph` per source paragraph in Preview mode, while Source
mode substitutes nothing and the buffer stays raw Markdown throughout.

## Acceptance criteria

- [ ] In Preview, headings are scaled by level, emphasis and strong are
      applied, lists and block quotes are shaped, thematic breaks are
      drawn, links are presented as links, and Markdown punctuation is
      not displayed as literal text (R10).
- [ ] Tables render via the attachment from ticket 01 as a true grid with
      aligned columns (R11).
- [ ] Images are **not** rendered; they degrade to readable styled text,
      not raw syntax (R12).
- [ ] In Source mode, the delegate substitutes nothing; raw bytes lay out
      unchanged.
- [ ] The buffer is never rewritten; rendered text is never written back
      to it; markup is never hidden via clear foreground colours or
      near-zero font sizes (N4).
- [ ] Fixtures cover bold, italic, block quote, nested list, image,
      heading below H1, table, and thematic break — and assertions check
      what a reader actually sees, not just that an attribute was
      attached to a source range (E.14, N9).

## Context

- Requirements: R10, R11, R12, N4; Architecture components 7 "Preview
  renderer" and 8 "Table attachment"; Data model `SubstitutionCache`,
  `TableLayout`; Key flow "Render Preview".
- Planning doc `(2026-08-16) v1.1.md`: E.12–E.14; "Recommended
  direction" → "Rendered Preview: paragraph substitution, one buffer" —
  read this section for the full rationale (only option that can hide
  markup, preserves disk truth, preserves folding, preserves source
  mapping, fixes the H.22 full-reparse performance problem as a side
  effect).
- Depends on ticket 01 for the table attachment type.
- Requirements testing note: the v1 GFM fixture had no bold, italic,
  block quote, nested list, image, or heading below H1, and its test
  only asserted an attribute was attached — do not repeat that mistake.

## Subtasks

- [ ] Implement `NSTextContentStorageDelegate` returning a substituted
      `NSTextParagraph` per source paragraph in Preview mode.
- [ ] Cover emphasis, strong, block quotes, lists (incl. nested),
      thematic breaks, links, and heading levels.
- [ ] Integrate the ticket-01 table attachment for GFM tables.
- [ ] Degrade images to styled placeholder text.
- [ ] Build/extend the GFM fixture to exercise every covered element;
      write assertions against rendered output, not attribute presence
      alone.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

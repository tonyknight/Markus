---
id: 20260816-10-performance-to-budget
title: Performance to budget
type: chore
priority: high
status: in-progress
created: 2026-08-16
updated: 2026-08-17
closed:
notes: ''
parent:
depends_on:
- 20260816-04-fold-all-unfold-all-and-fence-placeholder
- 20260816-08-preview-rendering-via-paragraph-substitution
subtasks:
- id: T1
  title: Viewport-only drawing (dirty-rect culling), no full-fragment enumeration
  status: todo
- id: T2
  title: Gutter computes visible-range entries only
  status: todo
- id: T3
  title: Zero parses on fold/theme/zoom/mode-switch/resize
  status: todo
- id: T4
  title: Single SourceMap per BlockIndex.build
  status: todo
- id: T5
  title: Instrumentation counters + 5 MB fixture + counter and wall-clock tests
  status: todo
---
## Description

Every `draw()` enumerates *all* layout fragments with `.ensuresLayout`
and no dirty-rect culling; `drawGutter` calls
`packedSourceLineEntries()`, which is O(lines × fragments); `applyStyling`
runs a full cmark parse on every fold toggle, theme change, zoom step,
and container resize; and `BlockIndex.build` allocates a fresh
`SourceMap` inside its loop for every fenced code block. Each redraw is
at least quadratic in document size. This ticket gets drawing and
styling onto viewport-only, lazy, non-reparsing paths and adds the
deterministic instrumentation the budget table requires.

## Acceptance criteria

- [ ] Drawing enumerates only fragments intersecting the visible rect —
      no full-document enumeration per draw (P1).
- [ ] The gutter computes entries for the visible range only, never
      O(lines × fragments) (P2).
- [ ] Folding, theme changes, zoom steps, mode switches, and container
      resizes perform **zero** parses (P3).
- [ ] Styling and substitution are lazy and per-element; no
      full-document restyle on any interaction (P4).
- [ ] `BlockIndex.build` constructs one `SourceMap` per build, not once
      per fenced block (P5).
- [ ] Test-visible counters exist for parses performed, paragraphs
      substituted, and fragments enumerated per draw, and are asserted
      deterministically (N8).
- [ ] Wall-clock tests on the 5 MB fixture use a 2× margin over the
      budget table (Testing requirements, "How to test performance").
- [ ] A 5 MB Markdown fixture exists in the suite (none exists today).
- [ ] The Performance budgets table is met: continuous 16 ms/frame,
      keystroke 16 ms, discrete 100 ms, bulk 200 ms, load 1 s with first
      paint within 200 ms.

## Context

- Requirements: P1–P5, N8; Performance budgets table; Testing
  requirements → "How to test performance".
- Planning doc `(2026-08-16) v1.1.md`: H.21–H.24.
- Depends on ticket 08 (substitution is the thing that must become lazy)
  and ticket 04 (folding must trigger zero parses — the fold service has
  to exist first).
- Prefer counters over wall-clock: "If a timing test proves flaky,
  convert it to a counter assertion rather than loosening it
  indefinitely."

## Subtasks

- [ ] Add dirty-rect culling to `draw()`.
- [ ] Rework the gutter to compute visible-range entries only.
- [ ] Eliminate reparse triggers from fold toggle, theme change, zoom
      step, mode switch, and container resize.
- [ ] Make substitution invalidation lazy and scoped to the edited
      range.
- [ ] Fix `BlockIndex.build` to construct a single `SourceMap`.
- [ ] Add counters (parses performed, paragraphs substituted, fragments
      enumerated) and assert against them.
- [ ] Add the 5 MB fixture; add wall-clock tests with 2× headroom.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

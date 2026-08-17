---
id: 20260816-13-text-input-in-source
title: "Text input in Source"
type: feature
priority: high
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: "Deliberately last: built on a text view already fixed by chrome, Preview, folding, and performance work."
parent:
depends_on:
  - 20260816-02-window-geometry-and-appkit-main-menu
  - 20260816-08-preview-rendering-via-paragraph-substitution
  - 20260816-10-performance-to-budget
  - 20260816-12-fold-persistence-and-repair
subtasks:
  - id: T1
    title: NSTextInputClient conformance; caret geometry and blinking
    status: todo
  - id: T2
    title: Selection drawing; mouse drag and double/triple-click selection
    status: todo
  - id: T3
    title: Undo/redo coalescing
    status: todo
  - id: T4
    title: Dirty flag and updateChangeCount wiring, including undo
    status: todo
  - id: T5
    title: Debounced reparse off the keystroke path, integrated with fold repair
    status: todo
  - id: T6
    title: Preview selection maps to source ranges, including across a table
    status: todo
---

## Description

`FoldingTextView` has no `keyDown`, no `insertText:`, no
`NSTextInputClient`, no caret, and no selection drawing. The only text
mutation paths in the shipped app are Find/Replace and
`insertTextAtCaret`, which ignores the caret and always inserts at
offset 0; `DocumentSession.autosave()` is called only from a unit test;
`MarkdownDocument` sets `hasUndoManager = false`. This is the largest
single item in v1.1 and is scheduled **last by design** — after chrome,
Preview, folding, and performance have landed — so editing is built on a
text view that has already been fixed. Editing happens in Source mode
only; Preview stays a read-only, selectable reading surface.

## Acceptance criteria

- [ ] In Source, the caret is visible and placeable (R20).
- [ ] Typing inserts at the caret (R20).
- [ ] Selection works by mouse (drag, double/triple-click) and keyboard
      (R20).
- [ ] Undo and redo work (R20).
- [ ] The dirty flag and `NSDocument.updateChangeCount` follow every text
      change, **including undo and redo** (R21).
- [ ] Preview remains read-only but selectable; copying from it yields
      **source Markdown**, including when the selection covers a table
      (R22).
- [ ] Save writes the complete unfolded UTF-8 source — the saved file is
      byte-identical to the buffer (R23).
- [ ] Reparse is debounced and off the keystroke path; when it completes,
      the block index rebuilds and fold IDs repair against their anchors
      (ticket 12) rather than going stale.
- [ ] Keystroke-to-glyph holds the 16 ms frame budget on the 1 MB typing
      fixture; reparse never blocks it (Performance budgets table).

## Context

- Requirements: R20–R23; Architecture component 12 "Text input (Source
  only)"; Key flow "Type in Source"; Performance budgets table
  (keystroke row, 1 MB fixture).
- Planning doc `(2026-08-16) v1.1.md`: "The editing decision — settled"
  — read this in full; it explains why editing is Source-only and why
  it is sequenced last. Also see Risks and assumptions: "Text input on a
  view that owns its layout manager is the largest single item... no
  `NSTextView` to inherit behaviour from."
- Depends on ticket 02 (window/menu chrome fixed), ticket 08 (Preview
  substitution, so Source vs. Preview behaviour is settled), ticket 10
  (performance budgets in place before adding the highest-risk
  interaction path), and ticket 12 (fold repair must exist before
  editing can break fold IDs).
- Typing fluency at 5 MB is explicitly out of scope (Constraints); the
  1 MB figure is the assumed typing-fluency target per Requirements
  "Open questions" — confirm this is still current before implementing.

## Subtasks

- [ ] Implement `NSTextInputClient` conformance: caret geometry,
      blinking, IME/dictation entry points.
- [ ] Implement selection drawing and mouse drag / double/triple-click
      selection; keyboard navigation.
- [ ] Implement undo/redo coalescing.
- [ ] Wire dirty + `updateChangeCount` from every mutation path,
      including undo/redo.
- [ ] Implement debounced reparse off the keystroke path; integrate with
      ticket 12's fold-ID repair on rebuild.
- [ ] Implement Preview selection → source-range mapping, including
      resolving a selection that spans a table attachment (ticket 01) to
      its full source range.
- [ ] Accessibility pass.
- [ ] Performance test: keystroke-to-glyph within 16 ms on the 1 MB
      fixture.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

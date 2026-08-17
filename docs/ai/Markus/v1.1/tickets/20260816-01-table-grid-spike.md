---
id: 20260816-01-table-grid-spike
title: Table grid spike
type: spike
priority: high
status: done
created: 2026-08-16
updated: 2026-08-16
closed: 2026-08-16
notes: 'Hard gate: sequenced first, decides whether ticket 08 can proceed as designed.'
parent:
depends_on: []
subtasks:
- id: T1
  title: Prototype NSTextAttachment sizing/measurement from column content
  status: done
- id: T2
  title: Draw aligned grid (borders, column widths) in the attachment cell
  status: done
- id: T3
  title: Attach full table source-range metadata to the attachment
  status: done
- id: T4
  title: Validate selection over the attachment can resolve to source range
  status: done
- id: T5
  title: Go/no-go call; if impractical, stop and reopen design
  status: done
plan_status: done
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

- [x] An `NSTextAttachment` subtype measures column widths from cell
      content and draws an aligned grid (R11).
- [x] The attachment carries the table's full source byte range so a
      later selection over it can resolve back to source Markdown (feeds
      R22 in ticket 13).
- [x] The attachment composes with folding: it behaves as a normal owned
      layout element and does not break `FoldingTextLayoutFragment`
      folding of surrounding content (N3).
- [x] **Hard gate documented:** a clear go/no-go decision is recorded on
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

- [x] Prototype attachment sizing/measurement from parsed GFM table cell
      content (columns, alignment).
- [x] Draw the grid: borders, aligned columns, per-cell text.
- [x] Carry the table's full source `Range<Int>` on the attachment
      (`TableLayout.sourceRange`).
- [x] Validate that a selection spanning the attachment can be resolved
      back to that source range (needed for R22 later).
- [x] Record the go/no-go decision and rationale in Notes.

## Implementation plan

Status: done
Current task: 

### T01: Parse GFM table structure from cmark AST

Add table extraction to the Markdown layer: rows (header + body),
per-cell plain text, per-column alignment, and the table's full source
byte range, walking `CMARK_NODE_TABLE` / `_TABLE_ROW` / `_TABLE_CELL`
via `cmark_gfm_extensions_get_table_columns/alignments/row_is_header`.

Files: new `Markus/Markus/Markdown/TableParsing.swift`; new test file
`Markus/MarkusTests/TableParsingTests.swift`.

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TableParsingTests`
- [x] done
### T02: Prototype TableAttachment sizing/measurement

New `NSTextAttachment` subclass that takes a parsed table and measures
each column's width from its widest cell (font metrics), overriding
`attachmentBounds(for:location:textContainer:proposedLineFragment:position:)`
to report total grid size.

Files: new `Markus/Markus/Editor/TableAttachment.swift`; new test file
`Markus/MarkusTests/TableAttachmentTests.swift`.

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TableAttachmentTests`
- [x] done
### T03: Draw the aligned grid

Override `image(forBounds:textContainer:characterIndex:)` on
`TableAttachment` to render borders, per-column alignment, and per-cell
text into a platform image sized to the measured bounds.

Files: `Markus/Markus/Editor/TableAttachment.swift`; extends
`Markus/MarkusTests/TableAttachmentTests.swift` with drawing assertions
(non-empty image, size matches measured bounds, border pixels present).

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TableAttachmentTests`
- [x] done
### T04: Carry source range; resolve selection back to it

Add `sourceRange: Range<Int>` to `TableAttachment` (from T01's parsed
table) and an `NSAttributedString.tableSourceRange(intersecting:)`
helper that, given a selection `NSRange` overlapping the attachment's
character, returns the table's full source range (feeds R22 in ticket
13).

Files: `Markus/Markus/Editor/TableAttachment.swift`; extends
`Markus/MarkusTests/TableAttachmentTests.swift`.

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TableAttachmentTests`
- [x] done
### T05: Validate composition with folding (N3)

Embed a `TableAttachment` into a `FoldingTextView`'s storage alongside
a foldable heading/fence, and assert folding elsewhere still collapses
to zero-height fragments, layout doesn't crash, and the buffer is
untouched — no production changes expected unless composition surfaces
a bug.

Files: new test file
`Markus/MarkusTests/TableAttachmentFoldingTests.swift`.

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TableAttachmentFoldingTests`
- [x] done
### T06: Go/no-go call and ticket-scope verification

No new production code. Record the go/no-go decision and rationale as
a ticket Notes entry; run the full three-destination suite required
for changes to the shared editor.

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test` then
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test` then
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test`
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-16
T05 done: composition with FoldingTextLayoutFragment validated at the NSTextLayoutManager level (TableAttachmentFoldingTests) — folded fragments still collapse to zero height, the attachment's own paragraph fragment lays out normally alongside them, and the attachment attribute survives layout unmangled. No production changes were needed. Found (not a blocker for this ticket, flagged for ticket 08): FoldingSession.applyStyling does a blind textStorage.setAttributes(_, range: full) on every fold/mode/theme/zoom change, which wipes any .attachment attribute in range. That path is v1's attribute-only styling, explicitly slated for replacement by ticket 08's NSTextContentStorageDelegate paragraph substitution; ticket 08 must not reuse setAttributes(_:range:) wholesale once it substitutes table attachments in, or it will strip its own attachments on the next fold toggle.

### 2026-08-16
GO. Hard-gate decision: a true, custom-drawn NSTextAttachment grid is practical on this stack — ticket 08 (Preview rendering via paragraph substitution) may proceed as designed. Evidence: TableAttachment (Markus/Markus/Editor/TableAttachment.swift) measures per-column widths from actual cell content via font metrics (T02), draws real borders plus per-cell aligned text into a rasterized image via attachmentBounds(for:...)/image(forBounds:textContainer:characterIndex:) — the standard cross-platform NSTextAttachmentContainer drawing hook, no NSTextAttachmentCell or platform-specific view provider required (T03). It carries the table's full source Range<Int> (TableLayout.sourceRange, from TableParsing.swift's cmark_gfm_extensions_get_table_* walk of CMARK_NODE_TABLE/_ROW/_CELL) and NSAttributedString.tableSourceRange(intersecting:) resolves any selection overlapping the attachment back to that whole range, satisfying R22's future need (T04). Composition with FoldingTextLayoutFragment was validated directly at the NSTextLayoutManager level: folding elsewhere in a document containing the attachment still collapses to zero height, the attachment's own paragraph fragment lays out normally and is never touched by folding, and the attachment attribute survives layout unmangled (T05, N3 satisfied). All three xcodebuild destinations (macOS, iPhone 17, iPad Pro 13-inch M5) pass with zero failures. One integration risk flagged for ticket 08 (see prior note): FoldingSession.applyStyling's blind setAttributes(_, range: full) on every fold/mode/theme/zoom change wipes .attachment attributes — ticket 08 must not layer table-attachment insertion under that call path unchanged.

## Review

**2026-08-16 — Verdict: minors-only (clean).** Reviewed by a fresh subagent against R11, N3, N4, N9, the Table attachment component, and the `TableLayout` data model, with the reviewer independently re-running the new suite (18 tests, macOS, all pass).

Confirmed: files touched match the Implementation plan exactly; no buffer rewriting or clear-color/near-zero-font hacks (N4); folding composition tested at the real `FoldingTextLayoutFragment`/`NSTextLayoutManager` level, not stubbed (N3); no tautological assertions (N9); `sourceRange` computed via `SourceMap` byte-scanning, which is UTF-8-safe (continuation bytes never collide with ASCII `\n`) — no UTF-8/UTF-16 offset-space bug found. GO call judged justified by what was actually built, correctly scoped to the spike's real unknown rather than over-building.

Findings (all Minor, none blocking):
1. `TableAttachment.swift:226` `tableSourceRange(intersecting:)` resolves only the first table it finds if a selection spans two tables — fine for this ticket's single-table scope, flag for ticket 13 (R22).
2. `TableParsing.swift:73` `sourceRange` includes leading blockquote/list-marker bytes when a table is nested — untested edge case, out of this spike's scope, flag for ticket 13 if it assumes an exact table-only slice.
3. Cell content is flattened to plain text for measurement/drawing (`[[String]]`), so inline emphasis/code/links inside cells aren't preserved — acknowledged in code comments as sufficient for the geometry spike; ticket 08 will need real `[[NSAttributedString]]` cells per the `TableLayout` model.
4. Commit granularity bundles each test file with its implementation (matches existing project convention, not a new regression).

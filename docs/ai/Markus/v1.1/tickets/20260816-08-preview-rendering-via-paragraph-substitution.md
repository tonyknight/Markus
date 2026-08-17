---
id: 20260816-08-preview-rendering-via-paragraph-substitution
title: Preview rendering via paragraph substitution
type: feature
priority: high
status: in-progress
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ''
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
plan_status: approved
current_task: T04
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

Status: approved
Current task: T04

Design note (read before touching FoldingSession): substitution is
implemented so that no rendered content or attachment is ever stored as
an attribute on `documentTextStorage` (the one authoritative buffer).
`PreviewSubstitutionIndex` is rebuilt from the current `String` on
demand (mode/text change) and handed to a `PreviewContentStorageDelegate`
which builds fresh `NSTextParagraph`s per query. Because nothing
substitution-related lives on the backing store, `FoldingSession
.applyStyling`'s existing blind `setAttributes(_, range: full)` cannot
"wipe" it — there is nothing on the buffer to wipe. Multi-line elements
(tables, wrapped paragraphs/quotes, fenced code) render their full
content on one anchor source line; their remaining source lines are
hidden by reusing the *already-tested* `FoldingTextLayoutFragment
.isCollapsed` zero-height mechanism (extended to cover
"substitution-continuation" ranges alongside fold-hidden ranges) rather
than inventing a second hiding mechanism — this keeps N3's "zero-height
owned fragments, never near-zero font size" guarantee intact by
construction.

- **T01: Delegate scaffolding + heading substitution + risk proof.**
  Files: `Markus/Markus/Editor/PreviewContentStorageDelegate.swift`
  (new), `Markus/Markus/Editor/FoldingTextView.swift` (wire
  `contentStorage.delegate`), `Markus/Markus/Markdown
  /PreviewSubstitution.swift` (new: `PreviewElement`,
  `PreviewSubstitutionIndex`, heading-only element collection to start).
  Prove: Source mode delegate returns nil for every paragraph (raw bytes
  unchanged); Preview mode substitutes headings with font scaled by
  level and the substituted text contains no literal `#`; substitution
  survives `setMode`/`setTheme`/`setZoomScale`/fold-toggle round trips
  (the FoldingSession risk, exercised directly).
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T02: Inline span rendering.** Emphasis (italic), strong (bold),
  strikethrough, inline code, links (URL as `.link`, brackets/parens
  absent from displayed string). Files: `PreviewSubstitution.swift`
  (inline-node-to-`NSAttributedString` walker), new
  `MarkusTests/PreviewSubstitutionTests.swift`.
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T03: Block quotes and lists.** Bulleted/ordered/task lists
  (including nested, via depth-tagged elements), block quotes, shaped
  via paragraph-style indentation — marker/`>` prefix absent from
  displayed string. Generalizes the continuation-line hiding from T01 to
  any multi-line element. Files: `PreviewSubstitution.swift`,
  `PreviewSubstitutionTests.swift`.
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T04: Thematic breaks.** Drawn as a rule (attachment or paragraph
  border), not literal `---`/`***`. Files: `PreviewSubstitution.swift`,
  `PreviewSubstitutionTests.swift`.
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T05: Table integration (ticket 01).** Table elements substitute to a
  `TableAttachment` built from `TableParsing.parseTables`; the table's
  other source lines hidden via the same continuation mechanism. Files:
  `PreviewSubstitution.swift`, `PreviewContentStorageDelegate.swift`,
  `PreviewSubstitutionTests.swift`.
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T06: Fenced code hiding + image degradation.** Fence delimiter lines
  hidden (content lines stay visible, monospace); inline images degrade
  to styled placeholder text carrying the alt text, not raw `![]()`
  syntax and not a real image (R12). Files: `PreviewSubstitution.swift`,
  `PreviewSubstitutionTests.swift`.
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T07: Fixture + reader-visible assertions.** Extend
  `MarkusTests/GFMPreviewFixture.swift` (or add a sibling preview
  fixture) covering bold, italic, block quote, nested list, image,
  heading below H1, table, and thematic break. Assertions read the
  *substituted/rendered* string a reader would see (no literal `#`,
  `**`, `>`, `- [ ]`, `[]()`, backticks; bold/italic traits present;
  table renders via `TableAttachment`; Source mode round-trips raw
  bytes unchanged). Files: `MarkusTests/GFMPreviewFixture.swift`,
  `MarkusTests/PreviewSubstitutionTests.swift` or new
  `MarkusTests/PreviewRenderingSubstitutionTests.swift`.
  Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`

- **T08: Ticket-level verification.** No production changes expected;
  fix whatever the three-destination run surfaces on iOS/iPadOS.
  Verify (all three, per Requirements — this ticket touches the shared
  editor/renderer):
  `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`
  `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test`
  `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test`

## Notes

Append-only running log. Each entry dated.

---
id: 20260816-08-preview-rendering-via-paragraph-substitution
title: Preview rendering via paragraph substitution
type: feature
priority: high
status: in-progress
created: 2026-08-16
updated: 2026-08-17
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
current_task: T08
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
Current task: T08

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

### 2026-08-17
T06 done: fence delimiter lines (opening/closing ```/~~~) now substitute to a markup-only element and collapse to zero height via the existing continuation-range mechanism (content line between them stays raw/visible, monospace via the fold-styling fallback); inline images degrade to a styled placeholder (icon + alt text, italic/muted) via a new `CMARK_NODE_IMAGE` case, never raw `![]()` syntax and never a real image (R12).

Found and fixed a real bug during T06, not an environment issue (this took a long debugging detour — recorded here so it isn't rediscovered): the first implementation used a **literally empty** `NSAttributedString(string: "")` as the substituted content for a fence delimiter's anchor line, handed to `NSTextParagraph(attributedString:)` in `PreviewContentStorageDelegate`. A zero-length `NSTextParagraph` representing a non-empty source range breaks TextKit 2's incremental layout — `ensureLayout()` never returns, and every symptom (xcodebuild/test-host processes idling in a clean `-[NSApplication run]` loop, near-zero CPU accumulated over many real minutes, reproducing identically across shells, subagents, and a full machine reboot) looked exactly like a stuck build-service/test-injection handshake rather than a call inside our own code hanging. Root-caused by bisection: isolated to the single `ensureLayout()` call via a reduced repro (empty test body → safe; body up through `setMode(.preview)` → safe; adding `ensureLayout()` → hangs), then confirmed the trigger was the zero-length substitution specifically (not the separate "also mark this line hidden" logic, which was ruled out first and left in place).

Fix: `PreviewElement` gained an explicit `isMarkupOnly: Bool` flag instead of inferring "this should collapse" from `rendered.length == 0`. The fence delimiter lines now substitute to a **single space** (`NSAttributedString(string: " ")`, length 1 — never truly empty) and are flagged `isMarkupOnly: true`; `PreviewSubstitutionIndex.build` checks the flag (not length) to add them to `continuationUTF16Ranges`, which is what actually drives the zero-height collapse via `FoldingTextLayoutFragment.isCollapsed` (N3) — visual hiding was always meant to come from that mechanism, not from the substituted content being empty.

One pre-existing test broke as a direct, correct consequence of T06 landing: `SourceLineMapTests.sourceLineMapUsesPackedYOmitsFoldedLinesAndDoesNotInventWrapNumbers` used a fixture containing a fenced code block and asserted "every line visible when nothing is folded" — true before T06, no longer true now that fence delimiters are legitimately hidden as markup independent of fold state (R15/N3, same rule ticket 04 established for headings/fences). Updated the test's expectations to exclude the fixture's two delimiter lines (5 and 7) rather than weakening or removing the assertion.

Verify (fresh, this session, correct worktree confirmed via `pwd`/`git branch` on every invocation after an earlier cwd-drift incident): `-only-testing:MarkusTests/PreviewSubstitutionTests` → TEST SUCCEEDED, 32/32; full macOS suite → TEST SUCCEEDED, 114/114, zero failures.

T07 done: extended `GFMPreviewFixture.markdown` to also cover bold, italic, an inline image, a block quote, a thematic break, and a nested list (table, task list, strikethrough, inline code, link, footnote, fenced code x2, math were already present) — every element T07 asks for now composes in one document. Added `previewModeRendersEveryCoveredGFMElementAsAReaderWouldSeeIt` (`PreviewSubstitutionTests.swift`): asserts the *substituted/rendered* string for each element (no literal `#`/`##`, `**`/`*`, `![](...)`, `>`, `---`, list markers, `~~`/backticks/`[](`, `- [ ]`/`- [x]`, fence backticks, table pipes), confirms the thematic break and table render via their real attachments (not a "no dash/pipe substring anywhere" check — a table's collapsed header-separator row is a hidden-but-still-enumerable paragraph whose raw text legitimately contains `---`-like runs, which the naive check would false-positive against), and confirms Source mode round-trips the full fixture's raw bytes unchanged after Preview mode substituted most of it (N4).

RED confirmed for two different real reasons in turn, not compile errors: (1) the thematic-break assertion as first written failed against the table's hidden separator row, fixed by checking for the actual `ThematicBreakAttachment` instead of string absence; (2) `PreviewRenderingTests.previewPaintsGFMAttributesOnTheSourceBuffer` (pre-existing, unrelated to this ticket's own tests) broke because the new fixture paragraph's wording happened to end in the word "inline", and that test's `range(of: "inline")` now matched the new plain-text word instead of the pre-existing `` `inline` `` code span it was written for — fixed by rewording the new sentence, not the older test.

Verify (fresh, correct worktree confirmed): `-only-testing:MarkusTests/PreviewSubstitutionTests` → TEST SUCCEEDED, 34/34; full macOS suite → TEST SUCCEEDED, 115/115, zero failures.

T08 done: three-destination ticket-scope verify, required because this ticket touches the shared editor/renderer. macOS: TEST SUCCEEDED, 115/115. Found and fixed one real, pre-existing cross-platform bug on first iOS run — `previewModeAppliesInlineCodeWithoutLiteralBackticks` (from T02) read `font.isFixedPitch`, an `NSFont`-only member; `UIFont` has no such property, so the whole `MarkusTests` target failed to compile on iOS. This had never been caught before because this was the first time any iOS destination was actually run against this ticket's branch. Fixed by dropping the platform-specific fast path and relying solely on the cross-platform `PlatformFont.monospaced(size:).fontName == font.fontName` comparison, which was already present as the check's fallback. iPhone 17 Simulator (after the fix): TEST SUCCEEDED, 110/110. iPad Pro 13-inch (M5) Simulator: TEST SUCCEEDED, 110/110 (one transient `FBSOpenApplicationServiceErrorDomain`/"RequestDenied" simulator-launch log line appeared mid-run — a known Simulator flakiness class, not tied to any failed test case; xcodebuild's own retry absorbed it, zero actual test failures, final result TEST SUCCEEDED). `bora dev lint` reports two pre-existing errors on this ticket file (`current_task`/`### Tnn:` heading-format mismatch) that already existed at the T05 commit, before any of this session's work — confirmed via `git stash`; caused by a mid-session `bora` version upgrade introducing a stricter linter than this ticket's plan section's original (non-`### Tnn`) heading style satisfies. Out of scope to fix here; flagged for the controlling session.

All eight plan tasks (T01–T08) complete. Working tree clean. Ticket `status:` left `in-progress`, Acceptance Criteria/Subtask checkboxes left unchecked, `bora-review` not run — per this project's convention, that is the controlling session's job.

### 2026-08-17 (review fix)

`bora-review` flagged one Critical finding: an empty ATX heading (CommonMark-valid, e.g. `# ` with no inline content) produced a `PreviewElement` with zero-length `rendered` and `isMarkupOnly` defaulted `false` — the exact same hazard class as T06's fence-delimiter bug (a zero-length `NSAttributedString` reaching `NSTextParagraph(attributedString:)` for a non-empty source range breaks TextKit 2's incremental layout), just via a different AST node, and nothing in the diff exercised it.

Fixed generally rather than case-by-case, per the reviewer's own recommendation: `PreviewElement.rendered`/`isMarkupOnly` are now `private(set)`, and the memberwise fields are replaced with a custom `init` that normalizes *any* zero-length `rendered` to a single space and forces `isMarkupOnly = true` at construction — so no call site (heading, paragraph, list item, thematic break, fence delimiter, or anything added later) can ever produce a zero-length substitution for a non-empty source range, by construction, rather than by each site remembering to guard itself. All existing call sites already used keyword arguments matching the new `init`'s signature; no call-site changes needed.

Added `previewModeHandlesAnEmptyHeadingWithoutHangingOrLeavingItVisible` (`PreviewSubstitutionTests.swift`) as a direct regression test — it calls `ensureLayout()` on an empty-heading fixture, which would hang (not just fail) if this guard regressed, exactly as the original bug did.

Verify (fresh, correct worktree confirmed): `-only-testing:MarkusTests/PreviewSubstitutionTests` → TEST SUCCEEDED, 36/36; full macOS suite → TEST SUCCEEDED, 116/116, zero failures, no hang.

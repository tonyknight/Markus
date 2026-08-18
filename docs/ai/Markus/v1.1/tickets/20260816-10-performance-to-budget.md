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

Status: approved
Current task: (all tasks complete; ticket-scope verify remains)

Design note (read before touching `FoldingTextView.swift`): `BlockIndex
.build` already hoists a single shared `SourceMap` per build (T04/P5 —
confirmed by reading the file; see T04 below), so this plan does not
re-implement that. The remaining four problems live in
`FoldingSession`/`FoldingTextView`: (1) `drawFragments`/
`packedLayoutHeight`/`packedSourceLineEntries` all funnel through
`enumeratePackedVisibleFragments`, which walks
`enumerateTextLayoutFragments(from: documentRange.location, options:
[.ensuresLayout])` to the very end of the document on every call — no
early exit once past the visible rect; (2) `packedSourceLineEntries`
additionally loops `for line in 1...sourceMap.lineStarts.count`,
testing every source line against the packed-fragment list regardless
of viewport — the literal O(lines × fragments) named in the ticket;
(3) `applyStyling` calls `MarkdownParser().previewSpans(...)` and (via
`rebuildSubstitutionIndex`) `PreviewElementCollector.collect(...)`,
each running its own independent cmark parse, on every call — and
`applyStyling` runs on every fold toggle, theme change, zoom step,
mode switch, and container resize (all of `setMode`/`setTheme`
/`setZoomScale`/`applyFolds`), even though only `loadMarkdown`/
`syncBlocksFromStorage` (real text changes) need a reparse.

### T01: Dirty-rect culling in draw + fragment-enumeration counter (P1)

Thread the real visible rect from `draw(_ dirtyRect:)`/`draw(_ rect:)`
down to `FoldingSession.drawFragments(in:visibleRect:)`. Change
`enumeratePackedVisibleFragments` to stop enumerating (return `false`
from the `enumerateTextLayoutFragments` closure) once accumulated
`packedY` passes `visibleRect.maxY`, and to skip the `body` callback
(no draw call) for fragments whose packed frame is entirely above
`visibleRect.minY` — bounding forced layout/draw work to "document
start through visible bottom" instead of the whole document. Add
`private(set) var fragmentsEnumeratedLastDraw: Int` on `FoldingSession`
(reset to 0 at the start of `drawFragments`, incremented once per
fragment visited by the enumeration) as the N8 counter proving P1.
`packedLayoutHeight()`/`packedSourceLineEntries()` keep calling the
unbounded (`visibleRect: nil`) path for now — full-height/full-gutter
correctness is still needed until T02 reworks the gutter; only the
real `draw()` call site passes a real rect.

Test (`FoldingTextViewTests.swift`): build a small fixture (~5 headings)
and a large fixture (~5,000 headings) with a bitmap `CGContext` and a
small visible rect near the top; call `session.drawFragments(in:
visibleRect:)` on each (reachable via `@testable import Markus`, the
method is internal) and assert `fragmentsEnumeratedLastDraw` is
bounded by a small constant and does **not** scale with document size
— proportional to the viewport, not the document (P1's own wording).

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/FoldingTextViewTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/FoldingTextViewTests`
- [x] done

### T02: Gutter computes visible-range entries only (P2)

Rework `packedSourceLineEntries()` to stop looping over every source
line. Instead: call `enumeratePackedVisibleFragments` bounded to the
real visible rect (reusing T01's early-exit) to get the small set of
currently-visible packed fragments, then for each visible fragment's
UTF-16 range, binary-search `SourceMap.lineStarts` (new
`SourceMap.lineNumber(atByteOffset:)` helper) to find the handful of
source lines it covers — never iterating the full `lineStarts` array.
`drawGutter` passes the view's real visible rect through
`session.sourceLineMap(visibleRect:)`. Add
`private(set) var sourceLinesScannedLastGutterCompute: Int` on
`FoldingSession` (N8 counter): increments once per line actually
examined via the bounded path.

Test (`GutterTests.swift`): same small-vs-large-document comparison as
T01, call `session.sourceLineMap(visibleRect: someSmallRect)` (or
`drawGutter` if it is easier to reach), assert
`sourceLinesScannedLastGutterCompute` is bounded and does not scale
with total document line count.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/Markus/Markdown/BlockIndex.swift` (SourceMap helper),
`Markus/MarkusTests/GutterTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/GutterTests -only-testing:MarkusTests/FoldingTextViewTests`
- [x] done

Implementation note: `visibleSourceLines`/`gutterLineNumbers()`/
`foldableSourceLines()` and the minimap's use of
`session.sourceLineMap()` all continue calling the unbounded
(`boundedBy: nil`) path unchanged — the minimap genuinely needs the
whole document's line map to draw a representative minimap, and
`jumpToSourceLine`/`scrollPackedYOnScreen` need to resolve an
off-screen target line/Y. Only `drawGutter` (the real per-frame paint
path, and the only thing the ticket names) was changed to pass the
view's real visible rect through `sourceLineMap(boundedBy:)`, and its
internal `foldable` set is now derived directly from the bounded map's
entries instead of calling the unbounded `foldableSourceLines()`.
`handleGutterClick` still uses the unbounded `foldableSourceLines()`,
which is correct and low-risk since it only runs once per click, not
per frame.

### T03: Zero parses on fold/theme/zoom/mode-switch/resize (P3)

Split "parse structure" from "render style". New file
`Markus/Markus/Markdown/PreviewParsing.swift`: `PreviewInlineNode`
(indirect enum mirroring cmark inline node kinds — text, softBreak,
code, emph, strong, strikethrough, link, image, group-passthrough) and
`ParsedPreviewBlock` (lines, indentLevel, and a `Kind` enum — heading,
paragraph, thematicBreak, fenceDelimiter, listItemLead, table — with
no fonts or colors baked in) plus `PreviewStructureCollector.collect
(markdown:) -> [ParsedPreviewBlock]`, a pure port of today's
`PreviewElementCollector.collect`'s cmark walk (including the
`TableParsing.parseTables` call) that captures structure only. In
`PreviewSubstitution.swift`, replace `PreviewElementCollector` with
`PreviewElementRenderer.render(_:tokens:zoomScale:) -> [PreviewElement]`
— the exact same font/color logic as today, but pure Swift, switching
over `ParsedPreviewBlock`/`PreviewInlineNode` instead of touching
cmark. `PreviewSubstitutionIndex.build` gains a
`build(markdown:elements:)` overload used by the cached path, keeping
`build(markdown:tokens:zoomScale:)` as a convenience
(parse-then-render) so no existing test call site needs to change.

In `FoldingSession`: add `private var parsedPreviewBlocks:
[ParsedPreviewBlock] = []`, `private var parsedSpans: [MarkdownSpan] =
[]`, `private(set) var parsesPerformed = 0`, and a `private func
reparse(markdown: String)` that populates both (incrementing
`parsesPerformed`) — called only from `loadMarkdown` and
`syncBlocksFromStorage` (the two real text-change entry points),
alongside the existing `blocks = BlockIndex.build(...)`.
`rebuildSubstitutionIndex` now calls `PreviewSubstitutionIndex.build
(markdown:elements: PreviewElementRenderer.render(parsedPreviewBlocks,
tokens:, zoomScale:))` — no parse. `applyStyling`'s `.preview` case
uses `parsedSpans` directly instead of calling
`MarkdownParser().previewSpans(...)`. Net effect: `setMode`/`setTheme`
/`setZoomScale`/`applyFolds` (fold toggle, and the resize path via
`updateTextContainerForGutter`) all reach `applyStyling` without ever
calling `reparse`.

Test (`PreviewSubstitutionTests.swift`): load a fixture, snapshot
`view.session.parsesPerformed`; toggle a fold, change theme, change
zoom, switch mode, and trigger a resize (`updateTextContainerForGutter`
via a frame/bounds change) — assert `parsesPerformed` is unchanged
after each (P3, live counter, N9). Then call `replaceSelection`/
`syncBlocksFromStorage` and assert it **does** increment — proving the
counter can fail, and that real text changes still reparse correctly.
Also re-run existing `PreviewSubstitutionTests`/`PreviewRenderingTests`
to confirm rendered output is unchanged by the refactor (regression,
not just a new assertion).

Files: `Markus/Markus/Markdown/PreviewParsing.swift` (new),
`Markus/Markus/Markdown/PreviewSubstitution.swift`,
`Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/PreviewSubstitutionTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`
- [x] done

### T04: Single SourceMap per BlockIndex.build (P5) — verify, don't reimplement

Confirmed by reading `Markus/Markus/Markdown/BlockIndex.swift`: ticket
12 already hoisted one shared `let sourceMap = SourceMap(markdown:
markdown)` in `BlockIndex.build`, used by every block (heading and
fence alike), not one per fenced block. No production change needed.
Add a small counter `nonisolated(unsafe) static var
constructionCount = 0` to `SourceMap.init` (test-only instrumentation,
matching this ticket's N8 counter philosophy) and a test that resets
the counter, builds a `BlockIndex` from a fixture with 3+ fenced code
blocks, and asserts `SourceMap.constructionCount == 1` — a live,
failing-if-regressed proof (N9) rather than re-deriving the fix.

Files: `Markus/Markus/Markdown/BlockIndex.swift`,
`Markus/MarkusTests/BlockIndexTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/BlockIndexTests`
- [x] done

Implementation note: the first version of this test used a bare
`nonisolated(unsafe) static var constructionCount` reset-then-measure
pattern. It failed non-deterministically in a full-suite run (passed
in isolation, failed alongside the rest of `BlockIndexTests` and again
alongside unrelated suites like `MarkdownParserTests`/
`TableParsingTests`) — Swift Testing runs `@Test` functions in
parallel by default, so other tests' own `BlockIndex.build`/
`SourceMap(markdown:)` calls, running concurrently on other threads,
inflated the shared counter between this test's reset and its
assertion. Fixed by replacing the bare global with a `@TaskLocal
SourceMap.constructionCounter: ConstructionCounter?` bound via
`withValue(_:operation:)` around each `BlockIndex.build` call — task-
local values are scoped to the dynamic extent of that call tree, so
concurrently-running unrelated tests (which never bind the task-local)
see `nil` and cannot inflate the count. Confirmed fixed by rerunning
`BlockIndexTests` alone, alongside each other, and inside the full
macOS suite.

### T05: Instrumentation counters + 5 MB fixture + counter and wall-clock tests (N8, Testing requirements)

New file `Markus/MarkusTests/LargeMarkdownFixture.swift`: a deterministic
generator producing a ~5 MB markdown document (mixed headings,
paragraphs, fenced code, lists — realistic, not one giant paragraph)
and a ~1 MB variant, for reuse by any test needing document-size-scaled
fixtures. Add `private(set) var substitutionQueryCount = 0` to
`PreviewContentStorageDelegate` (N8's "paragraphs substituted"
counter), incremented once per successful (non-nil) `textParagraphWith`
return, reset via a small test hook.

New file `Markus/MarkusTests/PerformanceBudgetTests.swift`:

- Counters (primary, deterministic): on the 5 MB fixture, draw with a
  small viewport at the top and assert `fragmentsEnumeratedLastDraw`
  (T01) stays small and independent of the 5 MB size; toggle a fold,
  change theme, change zoom, switch mode, resize — assert
  `parsesPerformed` (T03) stays flat on the 5 MB fixture specifically
  (the ticket's explicit ask); after a theme change + draw, assert
  `substitutionQueryCount` reflects only visible paragraphs, not the
  full document's paragraph count (P4).
- Wall-clock (secondary, 2× margin over the Performance budgets
  table): load the 5 MB fixture end to end < 2 s, with a first-paint
  proxy (time to first `ensureLayout()`/draw after `loadMarkdown`)
  < 400 ms; fold/unfold one block on the loaded 5 MB doc < 200 ms;
  `foldAll`/`unfoldAll` < 400 ms; a single `replaceSelection` edit
  (closest existing analogue to "keystroke to glyph" — real typing
  input lands in ticket 13) on the 1 MB fixture < 32 ms. Per the
  Requirements' own testing philosophy, convert any wall-clock
  assertion that proves flaky in CI to a counter assertion rather than
  loosening it.

Files: `Markus/MarkusTests/LargeMarkdownFixture.swift` (new),
`Markus/MarkusTests/PerformanceBudgetTests.swift` (new),
`Markus/Markus/Editor/PreviewContentStorageDelegate.swift`,
`Markus/Markus/Markdown/MarkdownPreviewRenderer.swift`,
`Markus/Markus/Editor/FoldingTextView.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/PerformanceBudgetTests`
- [x] done

### Ticket-scope verify (after T05)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```
- [ ] done

## Notes

Append-only running log. Each entry dated.

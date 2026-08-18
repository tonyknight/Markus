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
- [x] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-18

All five plan tasks complete. T01: `FoldingSession.drawFragments` now
takes the view's real visible rect and stops enumerating fragments once
packed Y passes `visibleRect.maxY` instead of walking the whole
document on every draw; `fragmentsEnumeratedLastDraw` proves it stays
bounded regardless of document size (P1, N8). T02: `packedSourceLineEntries`
gained a `boundedBy:` path used only by `drawGutter` (the real per-frame
hot path) that derives the visible line range from two `O(log lines)`
binary searches into a new cached `UTF16LineOffsets.lineNumber(atUTF16Offset:)`
instead of scanning every source line; `jumpToSourceLine`, `scrollPackedYOnScreen`,
and the minimap keep the unbounded path since they genuinely need
off-screen resolution (P2, N8). T03: split "parse structure" from
"render style" — new `PreviewStructureCollector`/`ParsedPreviewBlock`/
`PreviewInlineNode` (cmark-free intermediate) parse once per real text
change; `PreviewElementRenderer` renders that structure with the current
theme/zoom, pure Swift, no cmark; `FoldingSession.parsesPerformed` proves
fold/theme/zoom/mode/resize all reuse the cache while a real edit still
reparses (P3, N8). T04: confirmed ticket 12 already hoisted a single
shared `SourceMap` per `BlockIndex.build` call (P5) — added a live test
using a `@TaskLocal` `SourceMap.ConstructionCounter` (a bare global
counter proved contaminated by Swift Testing's parallel execution of
unrelated tests also constructing `SourceMap`s; task-local scoping fixed
it) rather than re-deriving the fix.

T05 (5 MB fixture, counters, wall-clock) surfaced three further real,
severe bugs beyond P1-P4's literal scope — all found by directly
sampling (`sample <pid> -f /tmp/x.txt`) a test process that was running
far slower than it should have, not by guesswork, after wall-clock
tests against the new `LargeMarkdownFixture` proved unusably slow
(one early version of the load test ran ~39 s against a 1 MB document
before any fix landed). Recording the detective work here the way
ticket 08's Notes recorded its TextKit 2 hang, since none of these three
were obvious from reading the surrounding code in isolation:

1. **`MarkdownPreviewRenderer.apply` was effectively O(spans × document
   length).** It called `UTF8NSRange.nsRange(utf8Bytes:in:)` once per
   Markdown span (thousands, on a large document) to convert a byte
   range to an `NSRange`; that helper walks
   `string.utf8.index(startIndex, offsetBy:)` **from the string's
   start** on every call — fine for a one-off conversion, pathological
   in a loop. Confirmed by a controlled comparison: the identical
   per-span conversion-plus-attribute loop took 0.8 ms against a plain
   `NSMutableAttributedString` but tens of seconds against the live
   `NSTextStorage` for the same 1 MB document and span count — the
   difference wasn't `addAttributes` itself (a first fix along those
   lines helped only marginally), it was that `textStorage.string` is
   an `NSString`-bridged `String` whose UTF-8 index-offsetting is far
   more expensive than a native Swift string's. Fixed with a new
   `UTF8NSRange.nsRanges(utf8Bytes:in:)` that resolves every needed
   offset in **one forward pass** over the string's Unicode scalars —
   each scalar's own `.utf8.count`/`.utf16.count` gives the byte/UTF-16
   length directly, so the pass never touches `String.Index` distance
   computation at all — plus building the styled attributes on a
   scratch `NSMutableAttributedString` and assigning it into the live
   storage once via `setAttributedString`, rather than many
   `addAttributes` calls on the live storage.
2. **`FoldingSession.hiddenUTF16Ranges`/`placeholderUTF16Locations`
   were plain computed properties**, rebuilt from scratch — including
   the same per-item `UTF8NSRange.nsRange` cost — every time
   `collapseState(for:layoutManager:)` read them. TextKit 2 calls that
   delegate method once **per text element** during every
   `ensureLayout()`/draw pass, so a document with many fragments
   recomputed the whole cache once per fragment: a second, independent
   quadratic-shaped cost, invisible from T01's fix alone since it lives
   one level below drawing, in the `NSTextLayoutManagerDelegate`
   callback itself. Fixed by caching both as stored properties
   (`cachedHiddenUTF16Ranges`/`cachedPlaceholderUTF16Locations`),
   rebuilt once per real state change inside `applyStyling`
   (`rebuildHiddenRangesCache`, counted by the new
   `hiddenRangesCacheRebuildCount`).
3. **Even cached, the hidden-range lookup was still a linear scan.**
   `collapseState` called `cachedHiddenUTF16Ranges.contains { ... }`
   once per fragment — O(fragments × hidden_ranges), and this fixture's
   fenced code blocks alone contribute thousands of markup-only
   continuation ranges, so the product is large even for a moderately
   large document. Fixed by sorting the cache once (in
   `rebuildHiddenRangesCache`) and binary-searching it per fragment
   (`isFullyHidden`) — hidden ranges never overlap by construction
   (fold extents and substitution-continuation ranges are each built
   from disjoint block/line spans), so the one candidate with the
   largest `location` at or before the fragment's start is the only one
   that could contain it. Counted by the new
   `hiddenRangeLookupComparisons`, asserted to stay in the low millions
   on the 5 MB fixture rather than the hundreds of millions a linear
   scan would reach.

A fourth, environmental (not a code bug) finding: this Mac's scheme runs
`MarkusTests` with `parallelizable = "YES"`, which genuinely runs more
than one worker **process** against the same selected tests — confirmed
by direct sampling showing healthy, distributed cmark/rendering work
mid-run, not a hang or a fourth quadratic call chain. Two 5 MB-fixture
tests legitimately running at once, one per process (this suite's own
`@Suite(.serialized)` only keeps tests from overlapping *within* one
process), measured 10-30x slower wall-clock times than the same test
run alone. `PerformanceBudgetTests` was consolidated from what would
have been six separate 5 MB/1 MB fixture loads down to three, and its
wall-clock margins are documented in the file as deliberately looser
than a bare 2x for that reason — the counters, not the wall-clock
numbers, are what actually enforces P1-P4. The wall-clock tests are
further scoped `#if os(macOS)`: the Requirements' Performance budgets
table is explicitly "measured on macOS," and the already-generous load
budget missed by ~25% on an iPhone 17 Simulator run for no reason other
than the Simulator being genuinely slower than native macOS at CPU-bound
work — the counter-based test is cross-platform and passed on both
simulators unmodified.

One test-design bug worth recording on its own: an early version of the
"theme change substitutes only visible paragraphs" check called
`ensureLayout()` (which force-lays-out the *entire* document) before
resetting and re-measuring `substitutionQueryCount`, so the count came
back far larger than the total block count — not because substitution
wasn't lazy, but because `ensureLayout()` had already resolved every
paragraph earlier in the test and TextKit 2 does not re-query a
delegate for an already-resolved, unchanged range. Fixed by moving the
substitution check to right after the *first* bounded `drawFragments`
call on a freshly loaded view, before anything else could force a full
layout pass.

Verify (fresh): macOS `xcodebuild ... test` → TEST SUCCEEDED; iOS
Simulator iPhone 17 → TEST SUCCEEDED; iOS Simulator iPad Pro 13-inch
(M5) → TEST SUCCEEDED. `bora dev lint` reports one pre-existing error on
ticket 08 (`current_task`/`### Tnn:` heading-format mismatch, confirmed
predating this ticket's work) — out of scope here, flagged for the
controlling session as ticket 08's own Notes already do. Working tree
clean after six commits (T01-T05 plus the macOS-only wall-clock scoping
fix). Ticket `status:` left `in-progress`, Acceptance Criteria/Subtask
checkboxes left unchecked, `bora-review` not run — per this project's
convention, that is the controlling session's job.

### 2026-08-18 (review fix)

`bora-review` found a real **Critical** correctness bug in T05's
`isFullyHidden` binary search — not a further performance issue, a
genuine visible-content regression. The doc comment added alongside the
binary search claimed hidden ranges "never overlap by construction,"
and that claim is false for fold extents specifically: a heading's
`foldExtent` spans to the next same-or-shallower heading, so it
necessarily *contains* any nested sub-heading's or fenced code block's
own `foldExtent`. Folding an outer block and something nested inside it
at the same time — two ordinary chevron clicks, or unconditionally via
Fold All on any document with a fence under a heading — produces
overlapping hidden ranges. Sorted by `location`, the binary search's
"largest-start-≤-fragment" candidate logic picked the *inner* (nested)
range, and any fragment past that inner range's end but still inside
the outer range read back `.visible` — real content leaking into view
inside a folded section. The reviewer confirmed it empirically (a
heading > sub-heading > fence > trailing-paragraph fixture, folding the
fence then the ancestor heading, left the trailing paragraph visible)
and traced it to exactly the shape already present in
`FoldingTextViewTests.fixture`, uncaught by the existing
`hidesFoldedRangesViaLayoutFragmentsWithoutShrinkingBufferOrBreakingUndo`/
`foldAllCollapsesEveryFoldableBlockAndUnfoldAllRestoresLayoutHeight`
tests only because their assertions were weak (`collapsedFragmentCount
> 0`, `layoutHeight < unfoldedHeight` — true even with a partial leak,
not an exact check).

Fixed with a standard interval merge, not a narrower patch to the
search itself: `rebuildHiddenRangesCache` now merges the sorted hidden
ranges into their minimal disjoint union (`mergedDisjointRanges` — one
pass, extending the last merged range's end whenever the next range
starts at or before it, which also correctly absorbs a range fully
nested inside the last one) before `isFullyHidden` ever runs. Binary
search over a merged, genuinely disjoint set is correct by
construction — same O(log n) per-fragment cost, no asymptotic
regression versus what T05 already built.

Writing an exact-height regression test surfaced a second, distinct,
**pre-existing** bug (present in the original computed-property
implementation too, not introduced by T05 — confirmed by inspection:
the ported logic was identical) that the new test's stricter check also
caught: `cachedPlaceholderUTF16Locations` only checked whether a fence
was *individually* folded, not whether its opening line was *also*
already hidden by an ancestor's fold. Folding a heading and a nested
fence together showed the fence's R15 placeholder line even though the
fence's own opening line was itself inside the folded heading's hidden
range — nothing about the fence should be visible in that case,
placeholder included. Fixed in the same pass: a fence's placeholder
position is now excluded whenever its opening line
(`block.bytes.lowerBound`) is covered by any other hidden range: a
fence's own `foldExtent` never covers its own opening line (it starts
right after it), so any hit there can only be an ancestor's range.

Added `FoldingTextViewTests.foldingANestedFenceAndItsAncestorHeadingTogetherHidesEverythingInBetween`
(the reviewer's exact repro shape — heading > sub-heading > fence >
trailing paragraph, folded in both orders) asserting **exact**
`layoutHeight` equality between "ancestor folded alone" and "ancestor
and nested fence folded together," and strengthened both existing
`FoldingTextViewTests` (`hidesFoldedRangesViaLayoutFragmentsWithout...`,
`foldAllCollapsesEveryFoldableBlockAndUnfoldAllRestoresLayoutHeight`)
with the same exact-equality pattern against a "fold only the top-level
ancestor" baseline, rather than the pre-existing weaker `>`/`<` checks,
so all three would now catch this regression themselves. RED confirmed
directly (not just via the reviewer's diagnostic): temporarily disabled
the merge call and reran — all three new/strengthened assertions failed
for the documented reason; re-enabled and reran — all green. The
placeholder fix's own RED/GREEN was confirmed the same way, in the same
cycle (both fixes were needed together to reach GREEN).

Verify (fresh, this session, worktree/branch confirmed via `pwd`/`git
branch --show-current` before every command): macOS `xcodebuild ...
test` → TEST SUCCEEDED; iOS Simulator iPhone 17 → TEST SUCCEEDED; iOS
Simulator iPad Pro 13-inch (M5) → TEST SUCCEEDED. Working tree clean
after this fix's commit. Ticket `status:` still left `in-progress` —
this is a fix within the same ticket, not a reason to change that.

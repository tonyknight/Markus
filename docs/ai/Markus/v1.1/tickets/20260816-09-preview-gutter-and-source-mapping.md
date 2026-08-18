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

Status: approved
Current task: (all tasks complete; ticket-scope verify remains)

Design note (read before touching `FoldingTextView.swift`): Ticket 08
already gives every `PreviewElement`/`ParsedPreviewBlock` a `lines:
Range<Int>` source range whose `lowerBound` is the anchor line a
multi-line block renders its whole content on — `continuationUTF16Ranges`
already hides every other line of that range from
`FoldingSession.packedSourceLineEntries()` (so a multi-line paragraph or
table already produces exactly one `SourceLineMap.Entry`). The one real
gap between that and R13's "a source line number at each rendered
block's start" is a fenced code block's **body** lines: only the opening
and closing fence delimiters become `ParsedPreviewBlock`s
(`PreviewParsing.swift`'s `.fenceDelimiter` case) — the code content
between them is untouched raw pass-through text, never marked as
anyone's continuation, so it still gets its own per-line
`SourceLineMap.Entry` today, and so do ordinary blank lines between
blocks (never covered by any cmark node). Both currently still draw a
gutter number per line under Preview, contradicting "one number per
block start." T01 fixes this by filtering **what the gutter numbers**,
not by rewriting the line map: it does not need new hiding/continuation
machinery, since nothing about layout or click targeting is wrong today
— only which of the already-computed entries the gutter chooses to draw
a number next to.

### T01: Block-anchored gutter renderer for Preview (chevrons + block-start numbers)

Add a cached `private(set) var previewBlockAnchorLines: Set<Int>` to
`FoldingSession`, computed once inside `reparse(markdown:)` (alongside
`parsedPreviewBlocks`, so it never costs a per-frame/per-viewport scan —
P2's bounding stays intact) as `Set(parsedPreviewBlocks.map(\.lines
.lowerBound))` unioned with every foldable block's own start line
(`blocks.compactMap { $0.foldExtent != nil ? $0.id.startLine : nil }` —
belt-and-suspenders against `PreviewStructureCollector`'s independent
cmark walk and `MarkdownParser`'s ever disagreeing on a line number for
the same heading/fence). In `FoldingTextView.drawGutter`, gate the
number-drawing loop (not the chevron loop, which stays exactly as it is
today — reusing the existing mechanism verbatim, not reinventing it) on
`mode == .preview ? session.previewBlockAnchorLines.contains(entry
.sourceLine) : true`. Update `gutterLineNumbers()` the same way, so it
stays the live, testable proxy for what the gutter actually draws (N9).
Source mode's behavior is provably unchanged: the gate is a no-op
outside `.preview`.

Test (`GutterTests.swift`): rewrite
`macGutterShowsSourceNumbersAndFoldChevronsInBothModes`, which currently
asserts `gutterLineNumbers() == visibleSourceLines` in **both** modes —
true before this ticket, no longer true for Preview after it, the same
"pre-existing test breaks as a direct, correct consequence" pattern
ticket 08's Notes recorded for `SourceLineMapTests`. Against the
existing heading/paragraph/fence fixture (7 source lines: heading,
blank, paragraph, blank, fence-open, fence-body, fence-close), assert in
Preview mode `gutterLineNumbers()` shows exactly one number per rendered
block's true start — see the Implementation note below for the exact
expected set and why it is `[1, 3, 5]`, not `[1, 3, 5, 7]` — while
`foldableSourceLines()` still contains `1` and `5` and chevrons are
still drawn at both. Assert Source mode keeps `gutterLineNumbers() ==
visibleSourceLines` (the full `1...7`), unchanged.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/GutterTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/GutterTests`

Implementation note (found via this task's own RED, corrects the design
note above): the design note's premise — "nothing about layout or click
targeting is wrong today" — turned out to be false for fences
specifically. A fence's opening delimiter is `isMarkupOnly` (ticket 08),
which makes `PreviewSubstitutionIndex.build` add the delimiter's own
line to `continuationUTF16Ranges` too, not just a multi-line element's
*other* lines — so the delimiter line collapses to zero height and
never gets a `SourceLineMap.Entry` at all, pre-existing and unrelated to
this ticket. `foldableSourceLines()`/`drawGutter`'s chevron loop both
keyed strictly off `block.id.startLine` being present in that entry
list, so **Preview never drew a fence chevron at all** before this task
— confirmed via the RED run (`foldableSourceLines() → [1]`, no `5`), not
assumed. `previewBlockAnchorLines` was corrected to exclude
`.fenceDelimiter` anchors entirely (both open and close — a reader sees
one fence, not two “blocks”) and rely solely on the foldable-block union
for a fence's one true number, and a new `FoldingSession
.nearestVisibleLine(atOrAfter:in:)` resolves a block's chevron/number
(and `handleGutterClick`'s reverse lookup, so what's drawn is exactly
what's clickable) to the nearest line that actually has an entry when
the block's own anchor doesn't — the drawn *number* is always the
block's true start line; only where it's drawn can differ.
`gutterLineNumbers()` for the fixture below is therefore `[1, 3, 5]`,
not `[1, 3, 5, 7]` as first sketched here. `drawGutter` was split into
`drawSourceGutterNumbersAndChevrons` (byte-for-byte the old loop) and
`drawPreviewGutterNumbersAndChevrons` (the new resolved-anchor loop) so
Source mode's path is untouched rather than threaded through the new
resolution logic. A dedicated test,
`previewFenceChevronResolvesToItsFirstVisibleLineAndStaysClickable`,
proves the fix end-to-end: `y(forSourceLine: 5) == nil` (the delimiter
really is invisible), then a real `handleGutterClick` at the fence
body's resolved position actually toggles `foldStore.isFolded` for the
fence's own `FoldID` — not just that a number appears somewhere.
- [x] done

### T02: Confirm the source-line anchor per substituted paragraph actually drives the gutter (multi-physical-line block)

Per the ticket's Context, ticket 08 already carries a source-line anchor
on every substituted paragraph (`PreviewElement.lines.lowerBound`,
consumed via `previewBlockAnchorLines` in T01) — this task does not add
new anchor-carrying infrastructure, it proves T01 actually consumes it
correctly for the case T01's own fixture doesn't exercise: a block whose
source spans **more than one physical line** merging into a single
rendered visual block, the concrete premise R13 is revising (a rendered
paragraph no longer occupying the same number of visual lines as its
source). Add a fixture with a paragraph wrapping 3 physical source
lines (e.g. three short lines with no blank line between them, which
cmark joins into one paragraph node) and assert, in Preview mode: (a)
`previewBlockAnchorLines` contains the paragraph's first physical line
and **not** its second or third; (b) `gutterLineNumbers()` shows exactly
one number for that block; (c) the y that number is drawn at
(`session.sourceLineMap().y(forSourceLine:)` on the anchor line) is the
same y the block's single rendered fragment actually occupies —
confirmed geometrically, not just by absence of the other two line
numbers.

Files: `Markus/MarkusTests/GutterTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/GutterTests`

Implementation note: confirmed, not reimplemented, exactly as the
Context section predicted — this test passed on its first run against
T01's already-landed production code with zero further changes to
`FoldingSession`/`FoldingTextView` (the same "verify, don't reimplement"
shape as ticket 10's T04). `previewBlockAnchorLines` already excludes
lines 4 and 5, `y(forSourceLine:)` already returns `nil` for both (no
separate entry exists to return), and `sourceLineHeight(forSourceLine:
3)` already matches a genuinely single-physical-line rendering of the
same text to within floating-point tolerance — T01's
`nearestVisibleLine`/`previewBlockAnchorLines` machinery, built for the
fence case, generalizes to an ordinary multi-line paragraph without any
special-casing.
- [x] done

### T03: Reconcile go-to-line, outline jump, and minimap against block anchors

Outline jump and the minimap turn out to need no production change,
confirmed rather than assumed: `OutlineJump.items` always targets
`block.id.startLine`, which is always a block's own anchor line (never
a continuation), so it was never affected by continuation lines lacking
their own `SourceLineMap.Entry`; `MacMinimapView`/`MacMinimapChrome`
resolve every click through `snapshot.map.sourceLine(atY:)`, which by
construction can only ever return a line that already has a
`SourceLineMap.Entry` (continuation lines have none to click on in the
first place), so minimap clicks were never able to name an unresolvable
line. Both get a Preview-mode regression test added, since the existing
coverage for each only exercised Source mode (`OutlineJumpTests`) or a
document with no multi-line substitution (`MacMinimapTests`).

Go-to-line is the one genuine gap: `FoldingSession.y(forSourceLine:)`
returns `nil` for a continuation line (a physical source line inside a
multi-line block's `lines` range other than its anchor), because
`SourceLineMap` never has an entry for it by design — so
`jumpToSourceLine` on such a target silently sets the caret (byte-offset
based, unaffected) but never scrolls, in Preview mode specifically. Fix
`FoldingSession.y(forSourceLine:)`: if `sourceLineMap().y(forSourceLine:)`
finds no direct entry and `mode == .preview`, look up the
`parsedPreviewBlocks` entry whose `lines` contains the requested line
and resolve to its anchor's y instead — the requested line's real
visual proxy, since the whole block renders as one anchored unit.

Tests (`EditorQoLTests.swift` or `GutterTests.swift`, `OutlineJumpTests.swift`,
`MacMinimapTests.swift`): (1) RED-confirm the go-to-line gap directly —
build the T02 three-physical-line-paragraph fixture, switch to Preview,
call `jumpToSourceLine` on the paragraph's *second* physical line (not
its anchor), assert `lastJumpedPackedY` is non-nil and equals `y(for
SourceLine: anchorLine)`; (2) add a Preview-mode variant of
`outlineListsBlockIndexHeadingsAndJumpSetsCaretEvenWhenFolded` (same
fixture, `setMode(.preview)`) confirming outline jump still lands
correctly when Preview substitutes the target heading's own rendered
line; (3) add a Preview-mode minimap test confirming
`MacMinimapView.handleClick`/`onClickSourceLine` on the T02 fixture only
ever names a line present in `session.sourceLineMap().visibleSourceLines`
and that `jumpToSourceLine` on that exact line resolves to a non-nil,
correct y — proving gutter, minimap, and go-to-line agree on the same
underlying map even though the gutter now numbers a strict subset of it.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/GutterTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/GutterTests -only-testing:MarkusTests/OutlineJumpTests -only-testing:MarkusTests/MacMinimapTests`

Implementation note: all three new/confirming tests landed in
`GutterTests.swift` rather than split across `OutlineJumpTests.swift`/
`MacMinimapTests.swift` as first sketched — they're really about the
gutter's block-anchoring reconciling with those three features, and
keeping them together made the shared fixtures (and the contrast with
T01/T02's fixtures) easier to follow; `OutlineJumpTests.swift`/
`MacMinimapTests.swift` were left untouched (no existing test needed
fixing). Outline jump and minimap needed no production change, exactly
as predicted — both new tests passed on first run. The go-to-line RED
was real and confirmed for the right reason
(`view.y(forSourceLine: 4) → nil` against a real 46.0pt expectation, not
a compile error) before the `FoldingSession.y(forSourceLine:)` fallback
was added.

The fallback's addition to `y(forSourceLine:)` — the same function T01/
T02's own tests already called to prove specific lines have *no* visual
position — broke two of those two earlier commits' assertions as a
direct, correct consequence (the same "pre-existing test breaks"
pattern ticket 08's Notes recorded): `previewFenceChevronResolvesTo...`
asserted `view.y(forSourceLine: 5) == nil` for the fence's invisible
opening delimiter, and `previewMultiPhysicalLineParagraphAnchorsTo...`
asserted the same for a paragraph's continuation lines. Both now assert
against `view.session.sourceLineMap().y(forSourceLine:)` directly (the
raw map, bypassing the new fallback) instead of the convenience
`view.y(forSourceLine:)` — preserving their original intent (proving
the map itself has no entry there) now that the higher-level accessor
is deliberately smarter for exactly that situation.
- [x] done

### Ticket-scope verify (after T03)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

## Notes

Append-only running log. Each entry dated.

### 2026-08-18

All three plan tasks complete. T01: Preview's gutter now numbers a
source line only at each rendered block's true start (R13) instead of
one per visible source line — a cached `FoldingSession
.previewBlockAnchorLines: Set<Int>` (rebuilt only in `reparse`, never
per frame, P2) built from every `ParsedPreviewBlock` anchor except
`.fenceDelimiter` (a fence emits one of those per delimiter, purely so
ticket 08's substitution machinery can hide each independently — a
reader sees one fence, not two) unioned with every foldable block's own
`FoldID.startLine`. Source mode's `drawGutter` path is untouched
(`drawSourceGutterNumbersAndChevrons`, byte-for-byte the old loop); a
new `drawPreviewGutterNumbersAndChevrons` handles Preview. T02:
confirmed, not reimplemented — a direct test with a genuinely
multi-physical-line paragraph passed against T01's already-landed code
on its first run, including a geometric check (rendered height matches
a single-physical-line reference) rather than absence alone. T03: fixed
a real gap in `FoldingSession.y(forSourceLine:)` (nil for a continuation
line of a multi-line Preview block, so go-to-line silently placed the
caret but never scrolled there) with a fallback to the containing
block's anchor, then to the nearest genuinely visible line; confirmed
(no production change) that outline jump and minimap click were never
affected, since both only ever target/resolve a line that already has a
`SourceLineMap.Entry` by construction — added Preview-mode regression
tests for both since neither had any prior Preview-mode coverage.

Found via T01's own RED, not assumed, and the most consequential finding
in this ticket: **Preview never drew a fence's fold chevron at all**
before this fix, a pre-existing bug orthogonal to numbering. A fence's
opening delimiter is always `isMarkupOnly` (ticket 08's R10 handling),
which makes `PreviewSubstitutionIndex.build` collapse the delimiter's
own line to zero height — so it never had a `SourceLineMap.Entry`, and
both the old chevron loop and `foldableSourceLines()`/
`handleGutterClick` keyed strictly off `block.id.startLine` being
present in that entry list. Confirmed empirically before writing any
fix: `foldableSourceLines() → [1]` on a fixture with a heading (chevron
present) and a fence (chevron absent). Fixed generally, not just for
numbering: a new `FoldingSession.nearestVisibleLine(atOrAfter:in:)`
resolves a block's chevron/number position, and — symmetrically —
`handleGutterClick`'s reverse lookup, to the nearest line that actually
has an entry when the block's own anchor doesn't (a fence's opening
delimiter, always; an empty heading, sometimes, per ticket 08's
zero-length-substitution guard applying equally to headings). The
*number drawn* is always the block's true anchor line; only *where* it
draws, and what a click there resolves to, can differ. A dedicated test
(`previewFenceChevronResolvesToItsFirstVisibleLineAndStaysClickable`)
proves this isn't just cosmetic: a real `handleGutterClick` at the
resolved position actually toggles `foldStore.isFolded` for the fence's
own `FoldID`, not merely that a chevron shape appears somewhere.

A second, smaller finding worth recording: adding T03's fallback to
`FoldingSession.y(forSourceLine:)` broke two of T01/T02's own
assertions as a direct, correct consequence (the same "later task
changes an earlier task's function, earlier test must be updated"
pattern ticket 08's Notes recorded for `SourceLineMapTests`) — both had
asserted `view.y(forSourceLine:) == nil` for lines with no entry of
their own, which is no longer true now that the convenience accessor
resolves through a fallback. Both were updated to assert against
`view.session.sourceLineMap().y(forSourceLine:)` directly (the raw map,
bypassing the fallback) instead, preserving their original intent
(proving the map itself has no entry there) rather than weakening or
deleting them.

All tests assert live, observable state per N9: actual
`gutterLineNumbers()`/`foldableSourceLines()` output (not attribute
presence), a real `handleGutterClick` call toggling real
`foldStore.isFolded` state, geometric height/position comparisons
against independently-rendered reference fixtures rather than
re-deriving expectations from the same code path under test, and a real
`jumpToSourceLine`/`MacMinimapView.handleClick` round trip rather than
inspecting internal state in isolation.

Verify (fresh, this session, worktree/branch confirmed via `pwd`/`git
branch --show-current` before every xcodebuild/git invocation): macOS
`xcodebuild ... test` → TEST SUCCEEDED (102s); iOS Simulator iPhone 17 →
TEST SUCCEEDED (112s); iOS Simulator iPad Pro 13-inch (M5) → TEST
SUCCEEDED (109s). `bora dev lint` reports one pre-existing error on
ticket 08 (`current_task`/`### Tnn:` heading-format mismatch, already
flagged and confirmed predating this ticket's work by tickets 08's and
10's own Notes) — out of scope here, same as those tickets noted.
Working tree clean after four commits (T01, T02, T03, plus one
`Status.md` refresh after the ticket-scope verify). Ticket `status:`
left `in-progress`, Acceptance Criteria/Subtask checkboxes left
unchecked, `bora-review` not run — per this project's convention, that
is the controlling session's job.

## Review

### 2026-08-18

**Verdict: Important**

Reviewed commit range `7cf9f49`..`0e36709` (T01 `7cf9f49`, T02
`bce4ba2`, T03 `b745e12`, Status refresh `de7b986`, Notes append
`0e36709`). Spec compliance, TDD evidence, commit-message format, and
cross-ticket isolation all check out; one performance-invariant
regression needs fixing before this is clean.

**Spec / correctness — clean.**
- Source mode's number+chevron path (`drawSourceGutterNumbersAndChevrons`)
  is a byte-for-byte lift of the pre-ticket loop; confirmed by reading
  the diff, not just trusting the commit message. Gate is a true no-op
  outside `.preview`.
- `previewBlockAnchorLines` is built once in `reparse(markdown:)` from
  `parsedPreviewBlocks` (excluding `.fenceDelimiter`, correctly — a
  fence emits two delimiter blocks but must number once) unioned with
  foldable-block start lines. Confirmed cached, not recomputed per
  frame/viewport.
- `FoldingSession.y(forSourceLine:)`'s new fallback (T03) checks
  `map.y(forSourceLine:)` first and only falls through when that is nil
  **and** `mode == .preview`; Source mode is unreachable through the
  fallback branch. Verified against the diff directly.
- The claimed pre-existing bug — Preview never drew a fence's fold
  chevron, because the opening delimiter is `isMarkupOnly` (ticket 08)
  and so has no `SourceLineMap.Entry` — is real and the fix
  (`nearestVisibleLine(atOrAfter:in:)`) is applied symmetrically: the
  chevron/number draw loop and `handleGutterClick`'s reverse lookup use
  the same resolution, so what's drawn is what's clickable. Confirmed
  by reading both call sites, not just the Notes' claim.
- Cross-ticket isolation confirmed: `git diff` across the full range
  touches only `Markus/Markus/Editor/FoldingTextView.swift` in
  production code. Ticket 08's `PreviewSubstitution.swift`
  (`isMarkupOnly`/`rendered` normalization) and ticket 10's
  `cachedHiddenUTF16Ranges`/`mergedDisjointRanges` machinery are
  untouched — no risk of reintroducing either ticket's fixed bugs.
- `OutlineJumpTests.swift`/`MacMinimapTests.swift` are genuinely
  untouched across the whole range, matching T03's claim that no
  production change was needed for either.

**Important — Preview's new gutter-draw loop reintroduces the O(document
× viewport) shape P2 was written to eliminate.**

`drawPreviewGutterNumbersAndChevrons` (FoldingTextView.swift, T01)
iterates `blocks` (every foldable block in the *whole document*) and
`session.previewBlockAnchorLines` (every rendered block's anchor in the
whole document — one per paragraph/heading/table/fence, not just
foldable ones) unconditionally, every draw call:

```swift
for block in blocks where block.foldExtent != nil {
    guard let displayLine = session.nearestVisibleLine(atOrAfter: block.id.startLine, in: map),
          let entry = map.entries.first(where: { $0.sourceLine == displayLine })
    else { continue }
    ...
}
for anchorLine in session.previewBlockAnchorLines.sorted() {
    guard let displayLine = session.nearestVisibleLine(atOrAfter: anchorLine, in: map),
          let entry = map.entries.first(where: { $0.sourceLine == displayLine })
    else { continue }
    ...
}
```

`SourceLineMap.y(forSourceLine:)` (`SourceLineMap.swift`) is a linear
scan (`entries.first { $0.sourceLine == line }`), not a dictionary
lookup, and `map.entries` is bounded to the visible rect (call it `V`
entries) by ticket 10 T02's `sourceLineMap(boundedBy:)`. So each item
in the two loops above costs up to two full `O(V)` scans inside
`nearestVisibleLine`, plus a third, entirely redundant `O(V)` scan via
`map.entries.first(where:)` to recover the `Entry` that
`nearestVisibleLine` already implicitly located. Total cost per draw:
`O((blocks + anchors) × V)` — proportional to whole-document size times
viewport size, not to the viewport alone.

This is the same shape of bug ticket 10 fixed for `packedSourceLineEntries`
(O(lines × fragments)) and its P2 acceptance criterion was written
specifically to prevent ("the gutter computes entries for the visible
range only, never O(lines × fragments)"). Contrast with
`drawSourceGutterNumbersAndChevrons` (Source mode, untouched by this
ticket): it also iterates all of `blocks`, but filters with an O(1) Set
lookup (`visibleLines.contains(...)`), giving `O(blocks + V)` — linear,
not multiplied. The new Preview path does not use that same pattern.

`previewBlockAnchorLines` is not bounded to foldable blocks — it
includes one anchor per rendered block (every paragraph, table, heading,
fence), so for an ordinary prose document this scales with total
paragraph count, not just heading/fence count. A document with a few
thousand paragraphs — not an exotic heading-stress fixture — would hit
this on every scroll frame in Preview mode.

No existing test catches this: ticket 10's own viewport-boundedness
stress test (`drawFragmentsEnumerationIsBoundedByViewportNotDocumentSize`
in `FoldingTextViewTests.swift`) uses a 5,000-heading fixture but only
exercises `.source` mode via `session.drawFragments`, never
`drawGutter` in `.preview` mode. `sourceLinesScannedLastGutterCompute`
(ticket 10's N8 counter) only measures `sourceLineMap(boundedBy:)`'s
own construction, not what `drawPreviewGutterNumbersAndChevrons` does
with the result afterward — so this ticket's targeted test suite
(GutterTests/OutlineJumpTests/MacMinimapTests) passing, and even the
project's fuller suite passing, would not surface this regression.

Suggested fix shape (not applied — Critical/Important findings go back
through bora-tdd/bora-debug, not fixed by review): iterate `map.entries`
(already bounded to `V`) as the outer loop instead of `blocks`/
`previewBlockAnchorLines`, testing anchor/foldable membership with an
O(1) Set lookup the way `drawSourceGutterNumbersAndChevrons` already
does — mirroring the existing Source-mode pattern rather than
introducing a new one. Separately, `nearestVisibleLine` could return the
resolved `Entry` (or its index) directly instead of just the `Int` line,
removing the redundant third scan regardless of the outer-loop fix.

**Minor.**
- `nearestVisibleLine`'s "an empty heading, sometimes" case (mentioned
  in the Notes as also needing resolution) has no dedicated test fixture
  — only the fence-delimiter case is exercised directly. The mechanism
  is shared and generic, so this is a coverage gap, not a suspected bug.

**Not re-run:** the human's fresh `xcodebuild` run this session
(GutterTests/OutlineJumpTests/MacMinimapTests, TEST SUCCEEDED) is
trusted as-is; the Important finding above is a latent complexity issue
no existing test is positioned to catch, so re-running the same suites
would not have changed the result.

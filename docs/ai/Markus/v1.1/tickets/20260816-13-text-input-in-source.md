---
id: 20260816-13-text-input-in-source
title: Text input in Source
type: feature
priority: high
status: in-progress
created: 2026-08-16
updated: 2026-08-18
closed:
notes: 'Deliberately last: built on a text view already fixed by chrome, Preview,
  folding, and performance work.'
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
- id: T7
  title: Accessibility pass
  status: todo
- id: T8
  title: Keystroke-to-glyph performance test on the 1 MB fixture
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

Status: approved
Current task: T08

Design note (read before touching `FoldingTextView.swift`): `FoldingTextView`
is a `PlatformView` (`NSView`/`UIView`) that owns its own TextKit 2 stack
directly (`textLayoutManager`, `textContainer`, `documentTextStorage`,
`contentStorage` — all public `let`s at lines ~1023-1027) — it is **not**
an `NSTextView` subclass, so there is no default caret/selection/input
behaviour to inherit; all of it is new work. `editingUndoManager`
(`FoldingTextView` line 1028) already exists and is already what
`override var undoManager` returns on both platforms — keep it as the
single view-owned undo manager rather than switching to
`NSDocument.hasUndoManager = true` and the responder-chain manager, since
tests construct `FoldingTextView` standalone (no window, no document) and
must keep working that way. `insertTextAtCaret(_:)` (1605-1615) is
test-only scaffolding — it always inserts at offset 0 and never calls
`session.syncBlocksFromStorage()` — do not extend it; `T01`'s real
`insertText(_:replacementRange:)` replaces its role. `replaceSelection(with:)`
(1213-1221) is the one existing precedent for "mutate then reparse":
`FindReplace.replace` (`storage.replaceCharacters` wrapped in
`beginEditing`/`endEditing`) then `session.syncBlocksFromStorage()`
(reparse + `foldStore.repair(against:)` + restyle + relayout) then
`onTextDidChange?()`. Every new mutation path (`insertText`, backspace/
delete, drag-and-drop if any) should route through the same
`FindReplace.replace`-shaped primitive for the immediate buffer edit, but
must **not** call `syncBlocksFromStorage()` inline once T05 lands — T05
debounces exactly that one call. Editing is Source-mode only (R20's
"editing decision"): gate every new input entry point on
`session.mode == .source`, refusing (or no-op'ing) in `.preview`; Preview
stays read-only/selectable per R22. `NSTextInputClient` and `keyDown`/
`mouseDown` selection are AppKit-only — implement behind `#if os(macOS)`,
matching the file's existing macOS/iOS split (`mouseDown` at 1337 is
already macOS-only, `touchesBegan` at 1362 is the iOS equivalent); per
N6 the iOS/iPadOS destinations must keep building and passing the
existing (non-editing) suite, they do not need new editing behaviour or
tests. There is no existing point↔UTF-16-offset or offset↔caret-`CGRect`
helper anywhere in the codebase — T01 builds it from
`textLayoutManager`'s own APIs (e.g.
`NSTextLayoutManager.enumerateCaretOffsetsInLineFragment`/
`textLayoutFragment(for:)`) composed with the existing packed-Y
translation in `FoldingSession` (`y(forSourceLine:)`,
`enumeratePackedVisibleFragments`), since folded/hidden content is
layout-collapsed and raw `NSTextLayoutFragment` geometry does not skip it
on its own. `PreviewSubstitutionIndex` (`PreviewSubstitution.swift`)
currently only maps source-anchor-UTF16-offset → rendered
`NSAttributedString`; it has **no reverse mapping** from a Preview
selection back to source — T06 builds that from `PreviewElement.lines`/
`previewBlockAnchorLines` (ticket 09), unioning every anchor whose
rendered span the selection touches. `NSAttributedString
.tableSourceRange(intersecting:)` (`TableAttachment.swift`) already
exists and resolves a selection over a table attachment to its source
byte range, but ticket 01's review flagged it resolves only the
**first** table when a selection spans more than one — T06 must fix
that, not just reuse it as-is.

### T01: NSTextInputClient conformance; caret geometry and blinking

`#if os(macOS)`. Add caret/selection state (reuse
`selectedUTF16Range`, already present at line 1237 — a zero-length range
is the caret) and a blink timer. Add the point↔offset and
offset↔`CGRect` helpers described in the design note (skip hidden/folded
UTF-16 ranges, per `foldStore.hiddenByteRanges(in:)`/
`rebuildHiddenRangesCache()`). Conform `FoldingTextView` to
`NSTextInputClient`: `insertText(_:replacementRange:)` (routes through
the `FindReplace.replace`-shaped mutate primitive from the design note,
registers one undo action per call — T03 coalesces multiple calls later),
`setMarkedText(_:selectedRange:replacementRange:)`/`unmarkText()`/
`markedRange()`/`hasMarkedText()` (real IME/dictation support, not
stubs), `selectedRange()`/`firstRect(forCharacterRange:actualRange:)`/
`characterIndex(for:)`. Draw the caret (blinking, `needsDisplay` on
toggle) in `draw(_:)`. Gate every entry point on `session.mode ==
.source`. Do not call `session.syncBlocksFromStorage()` synchronously
from `insertText` yet — wire the (still-synchronous, pre-T05) mutate
call directly for now so T02/T03 have something to build on; T05
introduces the debounce.

Files: `Markus/Markus/Editor/FoldingTextView.swift`, new
`Markus/MarkusTests/TextInputTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests`

### T02: Selection drawing; mouse drag and double/triple-click selection; keyboard navigation

`#if os(macOS)`. Extend `selectedUTF16Range` to a real anchor+extent
model if needed for drag selection (start point fixed, end point moves).
Draw the selection highlight (skip hidden ranges same as the caret).
Implement `mouseDown`/`mouseDragged`/`mouseUp` for click-to-place-caret,
drag-to-select, double-click (word) and triple-click (line/paragraph)
selection — reuse the point↔offset helper from T01; gate on `.source`
mode (existing `mouseDown` at 1337 already handles gutter clicks first,
fall through to the new selection logic only outside the gutter).
Implement keyboard navigation: arrow keys move the caret (skip hidden
ranges), Shift+arrow extends the selection, Cmd+arrow / word-boundary
navigation as a reasonable minimum (do not over-build beyond what R20
asks — "selection works by mouse and keyboard"). Implement `copy(_:)`
for Source-mode selection: slice `documentTextStorage.string` at
`selectedUTF16Range` onto `NSPasteboard.general` — trivial in Source
mode since the buffer *is* the display; T06 handles the Preview-mode
case separately.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/TextInputTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests`

### T03: Undo/redo coalescing

Coalesce consecutive single-character `insertText` calls (and
consecutive single-character deletes) into one undo group when they are
contiguous and arrive within a short time window (e.g. via
`editingUndoManager.beginUndoGrouping()`/`endUndoGrouping()`, or by
extending the previous registration's replacement text when the new
edit is adjacent) — typing "hello" should be one undo step, not five.
A non-contiguous edit (caret moved, then typed elsewhere) or a paste
always starts a new group. Keep using `editingUndoManager`
(`FoldingTextView` line 1028) — do not introduce a second undo manager.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/TextInputTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests`

### T04: Dirty flag and updateChangeCount wiring, including undo/redo

`onTextDidChange` (`FoldingTextView`) already fires after
`insertTextAtCaret`/`replaceSelection(with:)` and is already consumed by
`DocumentSession.init` to re-publish SwiftUI change notifications
(`DocumentSession.swift:37-39`) — but it is **not** called from
`undoLastChange()`/redo today, and `MarkdownDocument` never observes it
at all (`MarkdownDocument.swift`'s only `updateChangeCount` call site is
inside `write(to:ofType:)`'s `.changeCleared`, confirmed by grep). Make
every mutation path — `insertText` (T01), delete/backspace, undo, redo —
call `onTextDidChange?()`. Add a second callback (or extend the existing
one with a change-kind parameter) that `MarkdownDocument` sets to call
`self.updateChangeCount(_:)` with the correct
`.changeDone`/`.changeUndone`/`.changeRedone` kind, determined via
`editingUndoManager.isUndoing`/`.isRedoing` at the moment the callback
fires (both are real `UndoManager` properties — use them rather than
threading kind information through every call site by hand). Confirm
`DocumentSession.isDirty` (`editor.string != lastSavedText`,
`DocumentSession.swift:27-29`) already reflects undo/redo correctly once
undo/redo mutate `documentTextStorage` through the normal path (it
should, since `isDirty` is a plain string comparison) — this task is
about `NSDocument.updateChangeCount`/`isDocumentEdited`, not
re-implementing `isDirty`.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/Markus/Document/MarkdownDocument.swift`,
`Markus/Markus/Document/DocumentSession.swift`,
`Markus/MarkusTests/TextInputTests.swift`,
`Markus/MarkusTests/DocumentSessionTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests -only-testing:MarkusTests/DocumentSessionTests`

### T05: Debounced reparse off the keystroke path, integrated with fold repair

`session.syncBlocksFromStorage()` (`FoldingSession.swift:436-442`) is
already the exact "reparse + `foldStore.repair(against:)` (ticket 12) +
restyle + relayout" sequence — no new repair API is needed, only its
*timing*. Today `replaceSelection(with:)` calls it synchronously on
every call; T01's `insertText` currently does too (per T01's note, wired
"directly for now"). Change the keystroke path so the buffer mutation
and glyph display happen immediately (still synchronous — R20's
"typing inserts at the caret" is a same-frame requirement) but
`syncBlocksFromStorage()` is scheduled on a debounce timer (cancel and
reschedule on every new keystroke; fire after a quiet period comfortably
under the Bulk budget's 200 ms). `replaceSelection(with:)` (Find/Replace)
keeps calling `syncBlocksFromStorage()` synchronously — it is not a
keystroke-path caller and its existing synchronous-reparse test coverage
should not change. Add a counter (N8 style, alongside the existing
`session.parsesPerformed`) proving `insertText` does not increment
`parsesPerformed` before the debounce fires, and that it does after.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/TextInputTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests`

### T06: Preview selection maps to source ranges, including across a table

Build the reverse mapping described in the design note: for a Preview-
mode selection, find every rendered anchor (`previewBlockAnchorLines`/
`parsedPreviewBlocks`, ticket 09) whose rendered span intersects the
selection, and union each one's full source-line range
(`PreviewElement.lines` → convert to source text via the cached
`SourceMap`/`UTF16LineOffsets`) to produce the copied Markdown — Preview
selection is block-line-grained, matching how Preview content is already
modelled (this matches R22 as written: "copying yields source
Markdown", not a byte-exact mid-block slice). Fix
`NSAttributedString.tableSourceRange(intersecting:)`
(`TableAttachment.swift`) to resolve **every** table attachment the
selection intersects, not just the first (ticket 01's review flagged
this as the known gap) — union each table's `sourceRange` into the
result the same way as ordinary blocks. Implement `copy(_:)` for
Preview-mode selection using this mapping, writing the resulting source
Markdown substring(s) to `NSPasteboard.general`.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/Markus/Editor/TableAttachment.swift`,
`Markus/MarkusTests/TextInputTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests`

### T07: Accessibility pass

Add `NSAccessibility` conformance/overrides needed for a custom text
view acting as a real text field to VoiceOver: `accessibilityRole`
(`.textArea`), `accessibilityValue` (the visible text), `accessibilitySelectedText`/
`accessibilitySelectedTextRange`, `accessibilityVisibleCharacterRange`,
`accessibilityNumberOfCharacters`. Assert live behaviour per the
Requirements "How to test UI" rule (N9) — read these accessibility
properties back from a real `FoldingTextView` instance with real
content/selection, not a compile-time constant.

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/TextInputTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/TextInputTests`

### T08: Keystroke-to-glyph performance test on the 1 MB fixture

`PerformanceBudgetTests.oneMegabyteFixtureSingleEditStaysWithinAGenerousKeystrokeAdjacentBudget`
(`PerformanceBudgetTests.swift:187-209`) already exists as a placeholder
for exactly this, with a doc comment stating it uses
`replaceSelection` ("this codebase's closest existing analogue to
'keystroke to glyph' today") as a stand-in and that "a literal 2×
margin over the 16 ms keystroke budget is not achievable without ticket
13's debouncing." Rewrite it to drive the real `insertText` path from
T01/T05 instead of `replaceSelection`: assert (a) a counter
(`session.parsesPerformed`, or the T05 debounce counter) proves no
reparse runs synchronously on the keystroke path, and (b) a wall-clock
check on the 1 MB fixture close to the real 16 ms budget with the same
contention-aware margin reasoning already established in this file
(macOS-only, `#if os(macOS)`, generous but real headroom — not the
placeholder's 15 s).

Files: `Markus/MarkusTests/PerformanceBudgetTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/PerformanceBudgetTests`

### Ticket-scope verify (after T08)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

## Notes

Append-only running log. Each entry dated.

### 2026-08-18

All eight plan tasks (T01–T08) complete, one commit each. `FoldingTextView`
now has real caret/selection/input on macOS behind `#if os(macOS)`:
`NSTextInputClient` conformance with real IME/dictation support (T01),
mouse click/drag/double/triple-click selection and keyboard navigation
(T02), undo/redo coalescing (T03), `NSDocument.updateChangeCount`
wiring including undo/redo (T04), a debounced reparse off the
keystroke path integrated with ticket 12's fold repair (T05), a new
Preview-selection → source-Markdown reverse mapping including
multi-table selections (T06), an accessibility pass (T07), and a
rewritten keystroke-to-glyph performance test driving the real
`insertText` path (T08). iOS/iPadOS keep building and passing the
existing non-editing suite unchanged, per N6.

Several real bugs found via TDD (RED for a genuine reason each time,
not a compile error), recorded here in the style tickets 08/09/10 used
— root cause, not just "fixed":

1. **A leaked-timer crash, not the code bug it first looked like.**
   Running the full `TextInputTests` file (not any single test)
   intermittently crashed the shared AppKit test host with
   `EXC_BREAKPOINT` inside `FoldingTextView.__ivar_destroyer`,
   releasing the `hostWindow` ivar. Root cause: `prepareForEditing()`
   (test scaffolding predating this ticket) creates a real `NSWindow`
   with a genuine strong reference cycle (view retains window via
   `hostWindow`, window retains view via `contentView`) that ARC never
   breaks on its own; T01's new `becomeFirstResponder` override
   schedules a real, repeating system `Timer` for caret blinking, which
   — for any such leaked window/view pair a test never explicitly tore
   down — kept firing indefinitely against a stale view for the rest of
   the process's life. Fixed with two layers: a `deinit` invalidating
   the timer as a general backstop, and explicit `resignFirstResponder()`
   teardown at each of this file's five `prepareForEditing()` call
   sites (which stops the timer regardless of whether the underlying
   reference cycle ever actually deallocates). The same hazard applies
   to T05's debounce timer; `deinit` covers both.

2. **`NSUndoManager.registerUndo` requires an open group at call time —
   true even before this ticket**, but silently papered over by
   `editingUndoManager`'s default `groupsByEvent = true` supplying an
   implicit one automatically. T03's first coalescing implementation
   only opened a group for coalescing-*eligible* edits, so a plain
   multi-character `insertText` call (e.g. an IME commit) crashed
   outright with `NSInternalInconsistencyException: must begin a group
   before registering undo`. This first surfaced as a whole-process
   crash inside unrelated SwiftUI/AppKit rendering machinery when the
   full suite ran under this Mac's parallel test workers — a real
   instance of the exact contention class ticket 10's Notes already
   documented, which very nearly got misdiagnosed as environment noise
   a second time. Running the same suite with
   `-parallel-testing-enabled NO` separated the signal from that
   contention and surfaced the real, exact `NSInternalInconsistencyException`
   and its call site directly. Fixed: every non-continuing edit always
   opens its own group now, whether or not it is itself eligible to be
   continued by a future one.

3. **Once (2) was fixed, two separate single-character streaks with a
   caret move between them still collapsed into one undo step.** Traced
   with temporary `NSLog` instrumentation (`print()` and direct file
   writes were both silently dropped under App Sandbox — only `NSLog`
   survived and was actually captured) to `editingUndoManager
   .groupingLevel` jumping straight to 2 on the very first
   `registerUndo` of a supposedly-fresh group, not 1: `groupsByEvent`'s
   default `true` was auto-opening an *additional* implicit group
   nested inside this view's own explicit one on every `registerUndo`
   call, so "close one level, reopen" never reached the true outer
   boundary. Fixed by disabling `groupsByEvent` in `completeInit()` —
   its own documented escape hatch for managing grouping entirely by
   hand. This exposed a further, narrower regression: two *other*
   pre-existing bare `registerUndo` calls (`unmarkText()` and the
   pre-ticket `insertTextAtCaret` test helper, the latter used across
   many existing test files) had always silently relied on the
   automatic per-event group too; both needed the same explicit-group
   fix once the automatic fallback was gone.

4. **A build/test-tooling stall, confirmed environmental, not a hang in
   the app.** `xcodebuild test` piped through `| tee | grep` intermittently
   stalled for many minutes *after* the test suite itself had already
   printed "passed" for every case — confirmed via direct process
   inspection (`ps`, `sample`) that the app/test processes were idle,
   not spinning, and that a plain `>` file redirect (no pipe) avoided
   the stall consistently on retry. Recorded per the ticket brief's
   explicit ask to profile rather than assume, the same discipline
   ticket 10's Notes modeled for a different symptom.

Judgment calls made where the plan left a genuine gap, each recorded
at the point they were made and repeated here for visibility:

- T01 folded backspace/forward-delete/newline/tab handling in
  alongside `insertText` rather than waiting for T02, since the
  Design note's own sentence lists them together as mutation paths
  sharing one primitive; T02 kept arrow-key/word-boundary navigation
  as its own explicit scope.
- T01 added `FoldingTextView.redoLastChange()` alongside the existing
  `undoLastChange()` test helper; neither is wired to a menu item or
  Cmd+Z/Cmd+Shift+Z, since R3's Edit menu item list (Find, Go to Line,
  Fold All, Unfold All) does not include Undo/Redo.
- T02 wired Cmd+C directly in `keyDown` (checked ahead of
  `interpretKeyEvents`) since Cmd+letter combinations aren't part of
  AppKit's default text key-binding table and there is no Edit > Copy
  menu item to route it through the responder chain either.
- T06 relaxed T02's mouse-selection mode gate from Source-only to both
  modes (selection *mechanics* — click/drag/word/line detection — are
  mode-agnostic; only actual mutation stays Source-only), since R22
  requires Preview to be genuinely "selectable" and T02's plan text
  had explicitly deferred "the Preview-mode case" to T06 without
  restricting that deferral to `copy(_:)` alone — leaving mouse
  selection Source-only would have made T06's whole reverse mapping
  unreachable through real interaction.
- T06 fixed `tableSourceRanges` (renamed from the singular
  `tableSourceRange`) as its own standalone, directly-tested utility,
  but the Preview-selection reverse mapping itself uses a simpler,
  independently-robust line-range-based approach (`ParsedPreviewBlock
  .lines` via the cached `SourceMap`/`UTF16LineOffsets`) rather than
  invoking it — reconstructing a document-level rendered
  `NSAttributedString` with attachments correctly positioned to call
  it against would have added real coordinate-space complexity for no
  net gain the line-based approach doesn't already provide, including
  the multi-table case.
- T07 reports `accessibilityValue` as the raw buffer in both Source
  and Preview modes, and `accessibilityVisibleCharacterRange` as the
  whole document rather than a genuinely viewport-bounded slice —
  building a separate accessible rendering of Preview's substituted
  text, or a viewport-to-UTF-16 range API that doesn't exist anywhere
  else in the codebase today, is real, additional scope the plan does
  not ask for.

Verify (fresh, this session, worktree/branch confirmed via `pwd`/`git
branch --show-current` before every command): macOS `xcodebuild ...
test` → TEST SUCCEEDED (134.9s); iOS Simulator iPhone 17 → TEST
SUCCEEDED (112.1s); iOS Simulator iPad Pro 13-inch (M5) → TEST
SUCCEEDED (177.0s). `bora dev lint` reports only the same pre-existing
ticket-08 `current_task`/`### Tnn:` heading-format mismatch every
other ticket on this board has already flagged as predating its own
work. Working tree clean after eight commits (T01–T08). Ticket
`status:` left `in-progress`, Acceptance Criteria/Subtask checkboxes
left unchecked, `bora-review` not run — per this project's convention,
that is the controlling session's job.

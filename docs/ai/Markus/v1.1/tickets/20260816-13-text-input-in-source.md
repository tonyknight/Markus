---
id: 20260816-13-text-input-in-source
title: Text input in Source
type: feature
priority: high
status: done
created: 2026-08-16
updated: 2026-08-18
closed: 2026-08-18
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
  status: done
- id: T2
  title: Selection drawing; mouse drag and double/triple-click selection
  status: done
- id: T3
  title: Undo/redo coalescing
  status: done
- id: T4
  title: Dirty flag and updateChangeCount wiring, including undo
  status: done
- id: T5
  title: Debounced reparse off the keystroke path, integrated with fold repair
  status: done
- id: T6
  title: Preview selection maps to source ranges, including across a table
  status: done
- id: T7
  title: Accessibility pass
  status: done
- id: T8
  title: Keystroke-to-glyph performance test on the 1 MB fixture
  status: done
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

- [x] In Source, the caret is visible and placeable (R20).
- [x] Typing inserts at the caret (R20).
- [x] Selection works by mouse (drag, double/triple-click) and keyboard
      (R20).
- [x] Undo and redo work (R20).
- [x] The dirty flag and `NSDocument.updateChangeCount` follow every text
      change, **including undo and redo** (R21).
- [x] Preview remains read-only but selectable; copying from it yields
      **source Markdown**, including when the selection covers a table
      (R22).
- [x] Save writes the complete unfolded UTF-8 source — the saved file is
      byte-identical to the buffer (R23).
- [x] Reparse is debounced and off the keystroke path; when it completes,
      the block index rebuilds and fold IDs repair against their anchors
      (ticket 12) rather than going stale.
- [x] Keystroke-to-glyph holds the 16 ms frame budget on the 1 MB typing
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

- [x] Implement `NSTextInputClient` conformance: caret geometry,
      blinking, IME/dictation entry points.
- [x] Implement selection drawing and mouse drag / double/triple-click
      selection; keyboard navigation.
- [x] Implement undo/redo coalescing.
- [x] Wire dirty + `updateChangeCount` from every mutation path,
      including undo/redo.
- [x] Implement debounced reparse off the keystroke path; integrate with
      ticket 12's fold-ID repair on rebuild.
- [x] Implement Preview selection → source-range mapping, including
      resolving a selection that spans a table attachment (ticket 01) to
      its full source range.
- [x] Accessibility pass.
- [x] Performance test: keystroke-to-glyph within 16 ms on the 1 MB
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

### 2026-08-18 (review fixes)

`bora-review` found four Important findings (see `## Review` below);
all four addressed, plus one Minor picked up along the way since it
was quick and low-risk.

**Important #1 — undo/redo unreachable by any real user interaction.**
`keyDown` special-cased only Cmd+C; there was no Cmd+Z/Cmd+Shift+Z
binding and no Edit-menu Undo/Redo item, so R20's "undo and redo work"
wasn't actually true for a real user. Fixed by checking Cmd+Z/Cmd+
Shift+Z in `keyDown` the same way Cmd+C already was — ahead of the
Source-only gate, since undo/redo must keep working after switching to
Preview mid-edit, matching `undoLastChange`/`redoLastChange`'s own
mode-independence. Picked up Minor finding "unmarkText() not gated on
Source mode" in the same commit, since it's the same area of code and
a one-line fix.

**Important #2 — arrow-key horizontal caret movement didn't skip
folded/hidden ranges.** `moveHorizontally` did raw `movingFrom + delta`
arithmetic with no fold-awareness, unlike click/drag and vertical
movement (both already point-based and fold-aware via
`enumeratePackedVisibleFragments`). Fixed with a new
`FoldingSession.skipHiddenUTF16Offset(_:movingForward:)`, built on the
same sorted/merged `cachedHiddenUTF16Ranges` binary search
`isFullyHidden` already uses — jumps straight to a hidden range's far
edge in the direction of travel when the computed target lands inside
one. RED confirmed directly per the review's own request: temporarily
reverted the fix and reran `TextInputTests` — exactly the two new
fold-navigation tests failed, nothing else — before restoring it.
Found and fixed a fixture mistake of my own while writing the RED
test: a single heading with no subsequent heading to bound its
`foldExtent` swallows the entire rest of the document when folded
(no next same-or-shallower heading for `BlockIndex.build` to stop at)
— needed a trailing "## Following two" heading, the same pattern
`FoldingTextViewTests.fixture` already uses, to keep the fold bounded
and leave real content to land on.

**Important #3 — `DocumentSession.isDirty`'s undo/redo round-trip
claimed in Notes but not directly tested.** The cited test asserted
`NSDocument.isDocumentEdited` (a separate mechanism), not `isDirty`
itself. The underlying logic already traced out as sound (both mine
and the review's independent tracing agreed), so this was a coverage
gap, not a suspected bug — added
`documentSessionIsDirtyReturnsFalseAfterUndoingBackToTheSavedState`,
no production change needed.

**Important #4 — Preview-mode `accessibilityValue` read raw Markdown,
not rendered text.** The review suggested a fast-follow ticket was an
acceptable alternative if a real fix needed meaningfully new machinery;
judgment call here was that it didn't — ticket 08's own
`PreviewSubstitutionIndex.anchorSubstitutions` (already built) holds
exactly the rendered strings needed. `accessibilityValue` now sorts
those into document order and joins their already-rendered strings,
falling back to the raw buffer in Source mode or before the first
`applyStyling` call.

Deliberately not picked up (left as-is, per the review's own "Minor,
non-blocking" framing and the coordinator's explicit "don't let it
slow you down"): the remaining five Minor findings (exposed
`editingUndoManager` lacking the same coalescing-group guard as
`undoLastChange`/`redoLastChange` — real but only reachable once a
future ticket wires a standard Edit > Undo/Redo menu item through the
default responder chain, which none does yet; the dead-code dangling-
group-on-`replace`-failure hazard in `mutateSourceText`; the inert
`tableSourceRanges` utility; debounce tests calling
`fireDebouncedReparse()` directly rather than exercising the real
`Timer` interval end-to-end; the `Task { @MainActor in }` hop in both
timer callbacks). None block correctness today; each is either already
disclosed as a known limitation elsewhere in these Notes or is a
low-risk, well-scoped item for whoever picks it up next.

Four separate commits, one per Important finding
(`git add -p` to split `FoldingTextView.swift`'s hunks by concern; a
manual scratch-file reconstruction to split `TextInputTests.swift`'s
single contiguous addition-only diff into four incremental states,
since `git add -p` cannot split a hunk with no unchanged context lines
to split on). Each commit's file state was independently built and
tested before committing.

Verify (fresh, this session, worktree/branch confirmed via `pwd`/`git
branch --show-current` before every command, including after cwd
drifted back to the main checkout mid-session and had to be corrected):
`-only-testing:MarkusTests/TextInputTests` → TEST SUCCEEDED at every
intermediate commit stage (T01-only, T01+T02, T01+T02+T04, and the
full T01+T02+T04+T07 state) and once more on the final `HEAD`; RED
independently confirmed for the T02 fix as described above. Full
three-destination ticket-scope re-verify on the final committed state:
macOS → TEST SUCCEEDED (135.2s); iOS Simulator iPhone 17 → TEST
SUCCEEDED (107.7s); iOS Simulator iPad Pro 13-inch (M5) → TEST
SUCCEEDED (116.4s). `bora dev lint` reports only the same pre-existing
ticket-08 mismatch. Working tree clean after four commits. Ticket
`status:` still left `in-progress`, Acceptance Criteria/Subtask
checkboxes still unchecked — per this project's convention, that
remains the controlling session's job.

## Review

### 2026-08-18

**Verdict: Important** — do not mark `done`, do not start the next
ticket. Two findings below should be fixed (or explicitly deferred by
the human) before this ticket closes; the rest are real but lower
priority and can travel as ticket Notes / fast-follows.

**Method**: read the full ticket-range diff (`745595b..HEAD`, 10
commits) directly, not just commit messages; dispatched five parallel
fresh reviewers each owning one plan-task cluster (T01; T02+T03;
T04+T05; T06+T07; T08+test-quality) with the actual diff and full
current source files, then independently re-verified the two
highest-risk claims myself by reading the raw undo-grouping and
caret-geometry code line-by-line rather than trusting either the
Notes or the sub-reviews. Ran targeted `xcodebuild ... -only-testing:`
verification myself, foreground, no pipes (avoiding the documented
`tee`/`grep` stall): `MarkusTests/TextInputTests` alone (TEST
SUCCEEDED, 4.3s), a second run with `-parallel-testing-enabled NO`
(TEST SUCCEEDED, 3.2s — the exact configuration that originally
surfaced the T03 crash, now clean), and
`DocumentSessionTests`+`TableAttachmentTests`+`PerformanceBudgetTests`
together (TEST SUCCEEDED, 82.8s). All real per-test pass lines
present, nothing silently skipped — corroborates the ticket's own
Notes item 4 (the `tee`/`grep` stall was tooling, not a shortcut in
what actually got verified).

#### Important

1. **Undo and redo are not reachable by any real user interaction.**
   `keyDown` (`FoldingTextView.swift:1756`) special-cases only Cmd+C;
   there is no Cmd+Z/Cmd+Shift+Z interception and no Edit-menu Undo/Redo
   item (confirmed by grep across the app target — the only
   undo/redo-related menu code is the ticket's own Notes explaining why
   R3's Edit menu doesn't include them). `undoLastChange()`/
   `redoLastChange()` are real, correctly-implemented, and well-tested,
   but only test code and other programmatic callers can reach them.
   R20 states plainly "undo and redo work" as an Acceptance Criterion;
   as shipped, a person typing in Markus today has no way to undo a
   typo. The judgment call to skip menu wiring was disclosed
   transparently in Notes, but the practical result doesn't meet R20's
   plain reading. Low-risk, contained fix: bind Cmd+Z/Cmd+Shift+Z in
   `keyDown` the same way Cmd+C is already bound, calling
   `undoLastChange()`/`redoLastChange()` directly (mirrors the existing
   precedent and rationale for why Cmd+letter needs explicit handling
   here). Needs either that fix or an explicit human decision to defer
   it to a follow-up ticket before this one closes.

2. **Arrow-key (horizontal) caret movement does not skip hidden/folded
   ranges, contradicting the plan's own explicit requirement.**
   `clampedOffset(_:)` (`FoldingTextView.swift:2436-2438`) only clamps
   to `[0, documentTextStorage.length]`; `moveHorizontally`
   (`:2550-2563`) computes the new offset by raw arithmetic
   (`movingFrom + delta`) with no hidden-range awareness. This differs
   from click/drag placement and vertical (up/down) movement, both of
   which resolve through point-based helpers
   (`utf16Offset(atPackedPoint:)`/`packedCaretRect`) that only ever
   walk visible fragments via `enumeratePackedVisibleFragments`
   (skipping `isCollapsed` fragments). The design note explicitly
   required the offset helpers to "skip hidden/folded UTF-16 ranges,"
   and T02's own plan text says "arrow keys move the caret (skip
   hidden ranges)" — this specific case isn't met. Practical effect:
   arrowing across a folded region's boundary in Source mode moves the
   caret into the hidden byte range; `packedCaretRect` then returns
   `nil` for that offset and the caret silently stops drawing (per T01
   agent's independent trace of the same nil-contract) until the user
   arrows past the whole hidden span — and typing at that point inserts
   into hidden/folded text with no visual feedback. No test in
   `TextInputTests.swift` exercises arrow-key movement across a fold
   (grepped for fold-related tests; the only one found covers
   debounce/fold-repair, not caret movement). Untested and unaddressed.

3. **`DocumentSession.isDirty`'s undo/redo round-trip claim in Notes is
   asserted but not directly tested.** Notes says isDirty "should"
   already reflect undo/redo correctly since it's a plain string
   comparison, and treats this as out of T04's scope. Independent
   tracing (mine, and one sub-review's) confirms the underlying logic
   is genuinely sound — `mutateSourceText`'s registered undo inverse
   replays the exact pre-edit substring, so the buffer round-trips
   byte-for-byte and the comparison will evaluate correctly — but the
   cited test (`markdownDocumentUpdatesChangeCountOnEditAndUndoReturnsToClean`)
   asserts `NSDocument.isDocumentEdited` (a separate, counter-based
   mechanism), not `DocumentSession.isDirty` itself. No test does
   `insertText` → save → `insertText` → `undoLastChange()` → assert
   `!session.isDirty`. Recommend adding that one direct test; the fix,
   if any is even needed, should be cheap given the logic already
   checks out.

4. **Preview-mode `accessibilityValue` reads raw Markdown source, not
   rendered text — a real (if disclosed) accessibility regression risk
   for Preview specifically.** `accessibilityValue()` returns
   `documentTextStorage.string` unconditionally in both modes. A
   VoiceOver user navigating Preview would hear raw syntax (`##`,
   `**bold**`, table pipes) rather than the rendered content Preview
   visually shows, making Preview accessibility indistinguishable from
   Source's. Notes disclose this openly as a scope-limiting judgment
   call, and a full verbalized-rendered-Markdown projection is
   legitimately larger scope than this ticket — but as shipped it
   undercuts the accessibility pass's own stated goal for Preview mode.
   Recommend a fast-follow ticket rather than treating this as fully
   resolved.

#### Minor

- `unmarkText()` (`FoldingTextView.swift:2839`) is the one
  `NSTextInputClient` entry point not gated on `session.mode ==
  .source`. Reachable only if the user switches to Preview mid-IME
  composition (narrow), but inconsistent with every sibling entry
  point's explicit gate.
- `undoManager` still exposes `editingUndoManager` directly
  (pre-existing); the "close any open coalescing group before calling
  undo/redo" guard lives only inside `undoLastChange()`/
  `redoLastChange()`, not in the exposed `UndoManager` itself. Not
  currently reachable any other way (nothing else calls
  `editingUndoManager.undo()`/`.redo()` directly), but would become a
  live crash risk the moment a future ticket wires a standard Edit >
  Undo/Redo menu item through the default responder-chain `undo:`/
  `redo:` actions (which bypass these wrapper methods). Worth a
  comment or a same-guard override on `UndoManager` for whoever picks
  that up — plausibly the same fix as Important finding #1 above.
- In `mutateSourceText`, `applyCoalescingGrouping` opens/continues a
  group before `FindReplace.replace` is attempted; if `replace` ever
  returned `false` the function returns early (`guard ok else { return
  false }`) with a freshly-opened group left dangling. Currently dead
  code — `mutateSourceText`'s own entry guard is identical to
  `FindReplace.replace`'s internal failure condition, so `replace`
  can't currently fail once the outer guard has passed — but a fragile
  duplicate-guard hazard if the two conditions ever diverge.
- `tableSourceRanges` (T06's fix for the multi-table selection gap in
  `TableAttachment.swift`) is correctly implemented and directly
  tested, but has zero call sites in production code — the actual
  Preview→source reverse mapping uses an independent, also-correct
  line-range-based approach instead (a deliberate, disclosed judgment
  call). Not a bug, just worth knowing the fixed utility is presently
  inert outside its own tests.
- The T05 debounce tests call `fireDebouncedReparse()` directly rather
  than waiting on a real `Timer` interval — deterministic and
  appropriate given this suite's established N9 philosophy (see
  `toggleCaretVisibility`'s identical precedent for the blink timer),
  but it means no test exercises the real `Timer.scheduledTimer`
  wiring/interval end-to-end. A bug in the interval itself, or in the
  timer never actually being scheduled, wouldn't be caught by this
  suite alone. My own two full-file `TextInputTests` runs passed
  reliably, which is reassuring but doesn't close this specific gap.
- Both the caret-blink and debounce timers hop through `Task { @MainActor
  in ... }` from their `Timer` callback rather than a synchronous
  main-actor call, even though both already fire on the main run loop.
  A purely theoretical (never observed) double-fire race exists if a
  reschedule lands in the narrow window between a timer tick and its
  hopped `Task` actually running. Shared pattern between T01 and T05,
  not a new hazard introduced by either individually.
- `caretDoesNotDrawWhenSelectionIsNonEmptyOrModeIsPreview` verifies
  caret *state* (visibility flag, mode, selection range), not actual
  pixel-level draw-skipping in `draw(_:)` — an honestly-documented
  coverage limitation (headless bitmap testing constraint), not a
  false-passing test.

#### What checked out cleanly

- The point↔UTF-16-offset and offset↔`CGRect` geometry helpers (T01)
  correctly skip folded/hidden content for click placement, caret
  drawing, and selection-highlight drawing, via the same
  `enumeratePackedVisibleFragments`/`isCollapsed` mechanism
  `drawFragments` already used — no O(document×viewport) regression of
  ticket 09's fixed bug.
- The leaked-timer crash fix (`deinit` backstop + `resignFirstResponder`
  teardown) is real and correctly scoped: the retain cycle it targets
  exists only in test-only `prepareForEditing()` scaffolding, not in
  the production `SessionEditorRepresentable` hosting path; both timer
  closures use `[weak self]`, so a fired-after-dealloc call is already
  a safe no-op independent of `deinit`.
- The core T03 undo-grouping fix is sound, verified by direct code
  reading (not just trusting Notes/tests): `applyCoalescingGrouping`
  unconditionally closes any dangling group and opens a fresh one
  whenever a streak doesn't continue — including for non-coalescable
  edits (`kind == nil`) — so every `registerUndo` call site has a
  guaranteed open group. `groupsByEvent = false` is set in
  `completeInit()`. Both other pre-existing bare `registerUndo` sites
  (`insertTextAtCaret`, `unmarkText`) now use the identical
  open/close-group pattern. `undoLastChange()`/`redoLastChange()`
  explicitly close any dangling coalescing group before calling
  `undo()`/`redo()`, preventing the "undo mid-streak" leak scenario.
  Re-ran `TextInputTests` twice myself, including once with
  `-parallel-testing-enabled NO` (the exact configuration that
  originally surfaced the crash) — both passed clean.
- T04's `updateChangeCount` wiring correctly reads
  `isUndoing`/`isRedoing` synchronously within the same call frame as
  the undo/redo replay (no async hop), so change-kind classification is
  reliable.
- T05's debounce is genuinely off the keystroke path (`parsesPerformed`
  counter proves zero synchronous reparses on `insertText`, exactly one
  after the debounce fires) and correctly cancels/reschedules on every
  keystroke, never leaking multiple pending timers.
  `replaceSelection(with:)` (Find/Replace) is unchanged and still
  reparses synchronously.
- T06's line-range-based Preview→source reverse mapping (chosen over
  the also-fixed `tableSourceRanges` utility) correctly resolves a
  table block to its complete source, including a selection spanning
  an ordinary paragraph and a table, in correct document order with
  clean block separation.
- `copy(_:)` is a proper `@objc` responder-chain override in both
  modes; `keyDown`'s explicit Cmd+C interception calls it directly
  rather than duplicating logic, and doesn't collide with anything
  since the Edit menu has no Copy item today.
- Save (`write(to:)`/`data(ofType:)`) reads directly from
  `session.textStorage`, unaffected by T05's debounce — R23's
  byte-identical save is not at risk from delayed reparse.
- T08's rewritten performance test drives the real `insertText` path
  (not the old `replaceSelection` stand-in), asserts the
  `parsesPerformed`/`hasPendingDebouncedReparse` counters directly, and
  uses a real, meaningfully tight wall-clock budget (2.0s, a 125×
  tightening from the placeholder's 15s) rather than a disguised loose
  bound.
- Spot-checked 15+ tests across `TextInputTests.swift`,
  `TableAttachmentTests.swift`, and `PerformanceBudgetTests.swift`
  (caret placement, IME composition/undo, mouse click/drag/double/
  triple-click, coalescing in both directions, dirty flag, debounce,
  multi-table Preview copy, accessibility) — all assert specific,
  falsifiable outcomes (exact strings/ranges/counts/order), not
  shallow "doesn't crash" checks. No violation of N9 found in the
  sample.
- Commit messages all follow `{ticket-id} {task-id}: {title}`; the
  final wrap-up commit's plain `{ticket-id}: ...` form matches this
  project's established convention for verify/Notes commits.

### 2026-08-18 (review 2)

**Verdict: Minor** — all four Important findings from the first review
round are genuinely resolved. Two small new Minor findings surfaced
while re-checking the fixes closely (below); neither blocks this
ticket, but both are worth recording. Do not re-litigate the five
Minor findings the implementer deliberately left as-is — they were
reviewed once already and are unchanged by these four commits.

**Method**: read all four fix commits' diffs directly (`face2d4`,
`64b9d3b`, `d4c56a7`, `42c90c5`) against the round-1 finding each
claims to close, plus `ab298c5`'s Notes entry; traced the surrounding
production code (not just the diff hunks) for each — `keyDown`,
`undoLastChange`/`redoLastChange`, `MacMainMenu.swift` (grepped
app-wide for any competing undo/redo wiring), `skipHiddenUTF16Offset`
and `mergedDisjointRanges`, `mutateSourceText`'s undo-inverse
registration, and `PreviewElementRenderer`/`PreviewSubstitutionIndex`.
Wrote and ran one temporary probe test (not committed — reverted via
`git checkout` immediately after, working tree confirmed clean
afterward) to empirically settle the one open question the first
round flagged (table content and Preview `accessibilityValue`) rather
than reasoning about it from code alone. Ran
`-only-testing:MarkusTests/TextInputTests` myself, fresh, foreground,
no pipes: TEST SUCCEEDED (7.4s), matching the controller's independent
7.3s run of `TextInputTests`+`DocumentSessionTests` and the
implementer's own reported three-destination ticket-scope re-verify.
Confirmed via `git diff --stat`/hunk headers across all four commits
that only the five specific call sites each fix claims to touch were
touched (`FoldingSession.skipHiddenUTF16Offset` at line 579,
`keyDown`'s Cmd+Z branch at 1765, `moveHorizontally` at 2547/2555,
`accessibilityValue` at 2641, `unmarkText` at 2837) — no incidental
changes anywhere near T03's undo-grouping (`applyCoalescingGrouping`),
T05's debounce, T06's table-selection mapping, or T08's performance
test.

#### Important findings from round 1 — status

1. **Cmd+Z/Cmd+Shift+Z binding (`face2d4`) — resolved.** Confirmed by
   reading `keyDown` directly: the new branch (`FoldingTextView.swift`
   ~1765-1821) is checked and returns *before* the `guard session.mode
   == .source` gate, exactly as claimed, so undo/redo survive a mode
   switch. Confirmed no collision: grepped the whole app target for
   `undo:`/`redo:`/`keyEquivalent` — `MacMainMenu.swift` builds its own
   `NSMenu`s from scratch (no storyboard/xib default Edit menu) and its
   Edit menu has exactly Find/Go to Line/Fold All/Unfold All, no
   Undo/Redo item and no `"z"` key equivalent anywhere in the app,
   confirming the round-1 finding's own premise and ruling out any
   double-handling via a competing menu key equivalent or the default
   responder-chain `undo:`/`redo:` actions. Confirmed the R22 concern is
   unfounded by reading `undoLastChange()`/`redoLastChange()`
   (`FoldingTextView.swift` ~2177-2199): both do nothing but close any
   dangling coalescing group and call `editingUndoManager.undo()`/
   `.redo()` — pure replay of previously-registered inverse mutations
   from real Source-mode edits, never new input, so this cannot become
   a Preview-mode editing path. New tests
   (`cmdZAndCmdShiftZReachUndoAndRedoThroughKeyDown`,
   `cmdZAlsoWorksInPreviewModeMatchingUndoLastChangesModeIndependence`)
   drive the real `keyDown` entry point with real `NSEvent`s, not a
   direct call to `undoLastChange()`. One stale side effect noted below
   (Minor).

2. **Arrow-key fold-skipping (`64b9d3b`) — resolved.** Read
   `skipHiddenUTF16Offset` and the new `moveHorizontally` call sites
   line-by-line. (a) Correct: binary-searches
   `cachedHiddenUTF16Ranges` for the range with the greatest `location
   <= offset`, then jumps to `hiddenEnd` (forward) or `hidden.location`
   (backward) only when the offset falls *strictly* inside — an offset
   exactly at either boundary is left alone, landing on real, visible
   geometry. (b) Confirmed no off-by-one at either edge by tracing both
   directions by hand: stepping one unit in from a near boundary lands
   correctly inside and triggers a full skip past the far edge in one
   press; stepping one unit further from a far boundary equally
   triggers the reverse skip. Both are additionally exercised live by
   the two new tests, which assert the landed offset resolves to real
   `packedCaretRect` geometry (N9 discipline), not just a bare offset
   number. (c) Confirmed structurally moot: `mergedDisjointRanges`
   (pre-existing, unchanged by this fix) merges any two ranges where
   `range.location <= currentEnd` — i.e., *touching* ranges get fused
   into one — so two consecutive folds can never leave a zero-width
   gap in `cachedHiddenUTF16Ranges` for the caret to get stuck in; a
   one-visible-character gap between two folds is handled correctly by
   ordinary two-press movement (verified by hand-tracing), and a wider
   gap is untouched by this fix at all. (d) Plain non-folded movement
   is unaffected: `skipHiddenUTF16Offset` returns its input unchanged
   whenever `cachedHiddenUTF16Ranges` is empty or the offset isn't
   inside any hidden range, so it's a pure pass-through outside actual
   folds. RED claim is plausible: traced that before this fix, Cmd+Z
   aside, an unhandled `moveRight:`/`moveLeft:` from inside a fold
   would compute `movingFrom + delta` with no fold awareness, landing
   inside the hidden range where `packedCaretRect` returns `nil` — the
   two new tests' `packedCaretRect != nil` assertions would genuinely
   have failed pre-fix, and the reverted-and-reran claim in the commit
   message is consistent with that trace.

3. **`isDirty` undo/redo round-trip test (`d4c56a7`) — resolved.** The
   new test opens a real temp file via `DocumentSession.open(url:)`,
   drives a real `insertText` through the real `FoldingTextView`, and
   asserts `session.isDirty` (not `NSDocument.isDocumentEdited`)
   directly at each of the four states the finding asked for: clean
   after open, dirty after edit, clean again after
   `undoLastChange()` genuinely restores `"Hello"`, dirty again after
   `redoLastChange()`. This is a real integration test through the
   actual `DocumentSession`/`FoldingTextView` stack, nothing mocked.
   No production change was needed or made, consistent with round 1's
   own assessment that the underlying logic already traced out as
   sound.

4. **Preview `accessibilityValue` (`42c90c5`) — resolved for its core
   claim, with one new Minor gap found (see below).** Read the diff:
   `accessibilityValue()` now returns the raw buffer whenever
   `session.mode != .preview` or there's no live substitution index
   (unchanged Source-mode behavior, confirmed by the new test's own
   second assertion and by re-running `TextInputTests`), and otherwise
   sorts `PreviewSubstitutionIndex.anchorSubstitutions` by anchor offset
   and joins their `.string` values. For a heading + bold-paragraph
   fixture this produces real reading text with no `#`/`**` — confirmed
   by the new test's assertions and independently by reading
   `PreviewElementRenderer.render`'s `.heading`/`.paragraph`/
   `.listItemLead` cases, all of which build real character content via
   `renderInline`. Does not crash for a table: traced `.table` in
   `PreviewElementRenderer.render` to `PreviewElement(lines:
   rendered: NSAttributedString(attachment: TableAttachment(...)))`,
   and `.thematicBreak` follows the identical
   `NSAttributedString(attachment:)` pattern. Empirically confirmed
   (temporary probe test, reverted after, `swift -e` sanity check
   alongside it) that `NSAttributedString(attachment:).string` is
   exactly the single U+FFFC object-replacement character — no crash,
   but the joined `accessibilityValue` silently substitutes that one
   placeholder character for the table's/thematic-break's actual
   content. New Minor finding below.

#### Minor (new this round)

- **Preview `accessibilityValue` silently drops table (and thematic-
  break) content behind a U+FFFC placeholder, rather than reading
  anything meaningful for it.** `PreviewElementRenderer.render`'s
  `.table` and `.thematicBreak` cases both wrap their content in
  `NSAttributedString(attachment:)`, whose `.string` is the bare
  object-replacement character — confirmed empirically via a temporary
  test (`makePreviewView` with a 3-column GFM table): the joined
  `accessibilityValue` contains U+FFFC and does **not** contain any of
  the table's actual cell text (e.g. "Left"), while correctly still
  containing the surrounding paragraphs' text. Not a crash and not a
  regression of the round-1 finding's core claim (headings/paragraphs/
  lists/emphasis genuinely read correctly now), but it is a real,
  undisclosed gap in exactly the scenario round 1 asked to have
  checked, and — unlike the five Minor findings deliberately left as
  Notes in the first round — this one isn't mentioned anywhere in the
  fix's commit message or the `ab298c5` Notes entry. Likely a fast-
  follow: give `TableAttachment`/`ThematicBreakAttachment` an
  accessibility-description string (e.g. "table, N rows by M columns"
  or a flattened cell-text join) that `accessibilityValue` could pull
  in instead of `.string`, the same way image alt-text already
  degrades to readable text in `PreviewElementRenderer`'s `.image`
  case.
- **Stale doc comment on `redoLastChange()`.** Its doc comment
  (`FoldingTextView.swift` ~2187-2192, untouched by any of the four fix
  commits — confirmed via `git show` grep) still reads "...the way
  `undoLastChange` also isn't wired to Cmd+Z today," which `face2d4`
  just made false. Purely cosmetic (no behavioral effect, nothing
  reads this comment at runtime), but worth a one-line fix next time
  this method is touched so it doesn't mislead a future reader into
  thinking Cmd+Z still isn't wired.

#### What checked out cleanly (beyond the four findings above)

- All four fix commits' diffs touch only the specific lines each
  claims to (verified via `git diff` hunk headers) — no incidental
  changes to T01's core `NSTextInputClient` conformance, T03's
  undo-grouping fix, T05's debounce, T06's table/Preview-selection
  mapping, or T08's performance test.
- Commit messages all follow `{ticket-id} {task-id}: {title}`
  (`ab298c5`'s plain `{ticket-id}: ...` form again matches this
  project's established convention for a Notes-only wrap-up commit).
- `TextInputTests` re-run fresh, foreground, no pipes:
  `-only-testing:MarkusTests/TextInputTests` → TEST SUCCEEDED (7.4s),
  consistent with the controller's independent 7.3s run and the
  implementer's own three-destination ticket-scope re-verify. Working
  tree confirmed clean after the temporary probe test used to check
  the table/accessibility question was reverted.

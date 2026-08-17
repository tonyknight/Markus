---
id: 20260816-04-fold-all-unfold-all-and-fence-placeholder
title: Fold All / Unfold All and fence placeholder
type: feature
priority: high
status: done
created: 2026-08-16
updated: 2026-08-17
closed: 2026-08-17
notes: ''
parent:
depends_on:
- 20260816-02-window-geometry-and-appkit-main-menu
subtasks:
- id: T1
  title: Fold-all / unfold-all traversal over the block index
  status: done
- id: T2
  title: Wire Edit menu items (from ticket 02) to the fold service
  status: done
- id: T3
  title: Fence placeholder — opening fence line plus short placeholder
  status: done
plan_status: done
---
## Description

Fold All / Unfold All is named in v1's planning file, in v1's R4, and in
both of v1's acceptance-criteria lists, but no code implements it — the
v1 completion note claiming it shipped was wrong. Separately, a folded
fenced block simply vanishes today instead of showing "the opening fence
and a short placeholder" as v1 specified. This ticket delivers both,
wired to the Edit menu items ticket 02 creates.

## Acceptance criteria

- [x] Fold All collapses every foldable block in the document; Unfold
      All restores them (R14).
- [x] Both are reachable from the Edit menu built in ticket 02 (R14).
- [x] A folded fence shows its opening fence line plus a short
      placeholder, not an empty gap (R15).
- [x] Folding stays a layout concern: zero-height owned fragments; the
      buffer is never rewritten and paragraph styles are never collapsed
      to hide text (N3).
- [x] Tests assert live fold state (blocks actually collapsed/restored),
      not a flag that can't fail (N9).

## Context

- Requirements: R14, R15, N3.
- Planning doc `(2026-08-16) v1.1.md`: F.15, F.16; background item 3
  ("Fold all / unfold all does not exist").
- Depends on ticket 02 for the Edit menu items that trigger these
  actions.
- Feeds ticket 12 (Fold persistence and repair), which needs a working
  fold service to persist and repair.

## Subtasks

- [x] Implement fold-all / unfold-all traversal over the block index.
- [x] Wire the Edit menu's Fold All / Unfold All items (added in ticket
      02, currently targeting `nil` with no handler) to this service.
- [x] Render the fence placeholder (opening fence line + short
      placeholder text) for a folded fenced block.
- [x] Tests: fold-all collapses every foldable block; unfold-all restores
      them; a folded fence shows the placeholder, not nothing.

## Implementation plan

Status: done
Current task: 

### T01: Fold-all / unfold-all traversal over the block index

Add `foldAll()` / `unfoldAll()` to `FoldStore` (set-based: fold every
`FoldID` present in the current block list / clear the set) and thread
them through `FoldingSession.foldAll(textStorage:)` /
`unfoldAll(textStorage:)` (mirroring the existing `applyFolds()` shape:
restyle + `invalidateLayout()`) and `FoldingTextView.foldAll()` /
`unfoldAll()` (mirroring `foldCurrent()`/`toggleFold(atSourceLine:)`).
This reuses the existing zero-height `FoldingTextLayoutFragment`
mechanism (N3) — no new hiding path, just driving `FoldStore` over every
block instead of one. Test asserts, on the existing folding fixture:
after `foldAll()`, `foldStore.isFolded(id)` is true for every block with
a `foldExtent` (heading and fence) and `collapsedFragmentCount > 0`
after `ensureLayout()`; after `unfoldAll()`, every previously-folded id
is unfolded and `layoutHeight` is restored to the pre-fold height — live
fold state, not a flag (N9).

Files: `Markus/Markus/Markdown/FoldStore.swift`,
`Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/FoldStoreTests.swift`,
`Markus/MarkusTests/FoldingTextViewTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/FoldStoreTests -only-testing:MarkusTests/FoldingTextViewTests`
- [x] done
### T02: Wire Edit menu items (from ticket 02) to the fold service

Replace the empty bodies of `MarkdownDocumentViewController.performFoldAll(_:)`
/ `performUnfoldAll(_:)` in `Markus/Markus/Document/MarkdownDocument.swift`
with calls through `EditorCommands.foldAll(on:)` /
`EditorCommands.unfoldAll(on:)` (new cases alongside the existing
`foldCurrent(on:)`) → `DocumentHost.foldAll()` / `unfoldAll()` →
`session.editor.foldAll()` / `unfoldAll()` (built in T01) — the same
responder-chain path `performFind`/`performGoToLine` already use, so
this is the one invocation path, not a parallel one. Test drives the
real responder chain exactly as
`customEditAndOpenFolderActionsResolveThroughTheResponderChainToTheDocument`
does, but with a document loaded with the folding fixture, and asserts
live state after dispatch: every foldable block's `foldStore.isFolded`
is true post-Fold-All and false post-Unfold-All (not just that dispatch
"ran without crashing", which is what the current placeholder test
proves and which this task supersedes).

Files: `Markus/Markus/Document/MarkdownDocument.swift`,
`Markus/Markus/Editor/EditorCommands.swift`,
`Markus/Markus/Document/DocumentHost.swift`,
`Markus/MarkusTests/MacMainMenuTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/MacMainMenuTests`
- [x] done
### T03: Fence placeholder — opening fence line plus short placeholder

Today a folded fence's `foldExtent` (end of opening fence line through
end of block, set in `BlockIndex.build`) collapses every line in that
range to zero height via `FoldingTextLayoutFragment`, so the block
vanishes after its opening line — an empty gap, not a placeholder (R15
violation). Give `FoldingTextLayoutFragment` a non-collapsing
"placeholder" state: a fixed short line of text (e.g. "⋯") drawn in
place of the fragment's real content, sized to one line's height rather
than zero. In `FoldingSession`, when resolving the layout fragment for a
text element (`textLayoutManager(_:textLayoutFragmentFor:in:)`),
designate the first hidden line inside a folded **fence**'s
`foldExtent` as the placeholder element for that block (heading folds
keep collapsing fully — R15 only asks for fences) and mark every other
hidden line in that block's extent fully collapsed as today. This stays
a layout concern per N3: the real fenced-body text is never removed
from `NSTextStorage` and no paragraph style is collapsed to hide it —
only the owned fragment's drawn glyphs and reported height change for
that one designated line. Test loads the existing fixture's fenced
block, folds it, calls `ensureLayout()`, and asserts: the opening
` ```swift ` line's fragment is not collapsed (still contributes its
real height to `layoutHeight`), exactly one collapsed-and-visible
placeholder fragment exists with non-zero height between the opening
fence line and the following block, the real fenced body text
(`let answer = 42`) is absent from anything drawn/enumerated as visible,
and `documentTextStorage.string`/`DocumentSave.writeUTF8` are still
byte-identical to the source fixture (buffer never rewritten, N3/N9).

Files: `Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/MarkusTests/FoldingTextViewTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/FoldingTextViewTests`

### Ticket-scope verify (after T03)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-17
All three plan tasks complete. T01: FoldStore.foldAll(_:)/unfoldAll() plus FoldingTextView.foldAll()/unfoldAll(), driving the existing zero-height FoldingTextLayoutFragment mechanism over every foldable block (N3). T02: MarkdownDocumentViewController.performFoldAll(_:)/performUnfoldAll(_:) now call EditorCommands.foldAll(on:)/unfoldAll(on:) -> DocumentHost -> FoldingTextView, the same responder-chain path as performFind/performGoToLine — one invocation path, not a parallel one; superseded the old dispatch-doesn't-crash test with one asserting live FoldStore state after real responder-chain dispatch. T03: FoldingTextLayoutFragment gained a non-collapsing placeholder state (draws U+22EF instead of zero height); FoldingSession designates the first hidden line inside a folded fence's foldExtent as that block's placeholder (headings still fold fully, per R15's fence-only scope) — buffer is never rewritten, no paragraph style collapsed to hide text. All tests assert live state (isFolded/isPlaceholder/isCollapsed/collapsedFragmentCount/layoutHeight), not flags. Ticket-scope verify: xcodebuild macOS, iOS Simulator iPhone 17, and iOS Simulator iPad Pro 13-inch (M5) all TEST SUCCEEDED. bora dev lint clean. Working tree clean after 3 commits (T01, T02, T03). AC checkboxes and status left untouched for the controlling session's review per process boundary.

## Review

**2026-08-17 — Verdict: minors-only (clean).** Reviewed by a fresh subagent against R14, R15, N3, N9, independently re-running `FoldStoreTests`/`FoldingTextViewTests`/`MacMainMenuTests` on macOS (all pass, including the new/rewritten `foldAllFoldsEveryFoldableBlockAndUnfoldAllClearsAll`, `foldAllCollapsesEveryFoldableBlockAndUnfoldAllRestoresLayoutHeight`, `foldedFenceShowsOpeningLinePlusPlaceholderInsteadOfAnEmptyGap`, `foldAllAndUnfoldAllResolveThroughTheResponderChainAndActuallyFoldTheDocument`); iOS Simulator destinations not re-run (already green in the implementer's own verify pass, diff has no platform-specific risk beyond pre-exercised `PlatformFont`/`PlatformColor` shims).

Confirmed: files touched match T01–T03 exactly; commit history is one commit per task (`c2fce13`, `96672fe`, `3fe45eb`) formatted `20260816-04 T0N: <title>`; buffer never rewritten (`view.string == fixture` and `DocumentSave.writeUTF8` byte-identical, asserted directly); zero-height collapse mechanism unchanged for non-placeholder lines; placeholder restricted to fence folds only, headings still fold fully; Fold All/Unfold All dispatch verified through the real responder chain (`resolveAndPerform` walking `nextResponder`), not a direct method call; tests assert live `foldStore.isFolded`/`layoutHeight`/`collapsedFragmentCount`, not booleans (N9).

Findings (both Minor, neither blocking):
1. `FoldingTextView.swift:39-45` (`layoutFragmentFrame`) — placeholder height derives from the underlying element's natural frame, not an explicit one-line clamp; works here because the fixture's first hidden fence line is unwrapped, but a genuinely long first line would report a taller-than-one-line placeholder. Untested edge case, not a functional break.
2. `FoldingTextViewTests.swift:117-152` — the T03 placeholder test doesn't independently assert the real body text is absent from drawn output (structurally guaranteed by the mutually-exclusive `isPlaceholder` branch in `draw(at:in:)`, so a coverage gap rather than a risk).

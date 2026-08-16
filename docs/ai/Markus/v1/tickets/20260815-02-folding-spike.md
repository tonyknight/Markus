---
id: 20260815-02-folding-spike
title: Folding spike
type: spike
priority: high
status: done
created: 2026-08-15
updated: 2026-08-15
closed: 2026-08-15
notes: ''
parent:
depends_on:
- 20260815-01-multiplatform-scaffold
subtasks:
- id: S1
  title: Block index with fold extents
  status: done
- id: S2
  title: Fold store + full-buffer save
  status: done
- id: S3
  title: TextKit 2 hide folds in Source and Preview
  status: done
- id: S4
  title: Three-destination verify
  status: done
- id: S5
  title: Own NSTextLayoutManager fragment hide
  status: done
plan_status: done
---
## Description

Parse a file with cmark-gfm, build the block index, custom TextKit 2 view
hides heading and fence fold extents in Preview and Source, shared fold
state, save writes the full buffer. This ticket *is* the editor-view
decision; if it is janky, stop and reopen design.

## Acceptance criteria

- [x] Block index from cmark-gfm: ATX headings and fenced code blocks with source byte/line ranges
- [x] Fold/unfold a heading section and a fenced block in Preview and Source
- [x] Fold state is shared across the mode switch
- [x] Save writes the complete unfolded source
- [x] Caret/undo still work in Source after a fold (spike-quality, not polish)
- [x] Tests pass on Mac, iPhone simulator, and iPad simulator
- [x] Folds hide via owned TextKit 2 **layout fragments**, not collapsed paragraph styles on `NSTextStorage`

## Context

Requirements R4, R5, N3. Architecture: one TextKit 2 view, Swift block
index. Hard gate for v1. Parser lives in `Markus/Markus/Markdown/MarkdownParser.swift`.

## Subtasks

- [x] Block index
- [x] TextKit 2 fold layout in both modes
- [x] Shared fold store + full-buffer save
- [x] Three-destination verify
- [x] Own NSTextLayoutManager fragment hide

## Implementation plan

Status: done
Current task: 

### T01: Block index with fold extents
RED then GREEN: parser/index reports ATX heading and fenced-code **byte and line ranges**, plus **fold extents** (heading: from end of heading line through next same-or-higher heading; fence: body after the opening fence, keep opening fence visible). Fixture with H2, paragraph, nested H3, fence, following H2.
Files: `Markus/Markus/Markdown/MarkdownParser.swift`, `Markus/Markus/Markdown/BlockIndex.swift` (or extend parser types), `Markus/MarkusTests/BlockIndexTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T02: Fold store and full-buffer save
`FoldStore` keyed by stable FoldID (kind + start line). Toggle fold; Source and Preview share one store. A save helper writes `NSTextStorage` / full UTF-8 **including folded extents**. Tests prove folded view state does not shrink the buffer.
Files: `Markus/Markus/Markdown/FoldStore.swift`, `Markus/MarkusTests/FoldStoreTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T03: TextKit 2 hide folds in Source and Preview
One custom view (AppKit + UIKit wrappers / SwiftUI representable) using TextKit 2. Applying fold extents **hides those source ranges in layout** in both Source (raw text) and Preview (attributed GFM sufficient for headings + fences). Same folds after mode switch. Spike UI may toggle folds via test hooks or a simple control; gutters are not required yet. If layout/caret/undo cannot hide ranges honestly, **stop and report** — do not invent a new stack.
Files: `Markus/Markus/Editor/FoldingTextView.swift` (and platform wrappers as needed), `Markus/MarkusTests/FoldingTextViewTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T04: Three-destination verify
Same tests on iPhone and iPad simulators.
Files: none unless a destination-specific fix is required
Verify:
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
- [ ] todo
- [x] done

### T05: Own NSTextLayoutManager fragment hide
Replace stock `NSTextView`/`UITextView` as layout owner. A custom view owns `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`, implements `textLayoutFragmentFor`, and uses `FoldingTextLayoutFragment` (zero height / skip draw) for folded extents. **Remove** `applyCollapsedParagraphStyles` as the hide mechanism. Tests must: (1) `collapsedFragmentCount > 0` when heading+fence are folded, (2) unfold restores Source layout height vs Source unfolded height (same mode), (3) save still full UTF-8, (4) spike-quality insert+undo in Source. Do not wrap STTextView/CodeEditSourceEditor in this ticket.
Files: `Markus/Markus/Editor/FoldingTextView.swift`, `Markus/MarkusTests/FoldingTextViewTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
then
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
- [ ] todo
- [x] done

### 2026-08-15
T01: Block index reports ATX/fence byte+line ranges and fold extents (heading through next same-or-higher; fence body after opener). macOS MarkusTests passed.

### 2026-08-15
T02: FoldStore is shared across Source/Preview; DocumentSave.writeUTF8 writes full NSTextStorage UTF-8 including folded extents. macOS MarkusTests passed.

### 2026-08-15
T03: TextKit 2 view hides heading/fence extents in Source and Preview via collapsed paragraph styles on the full NSTextStorage (characters unchanged). NSTextLayoutFragment subclass was not invoked by NSTextView; layout still shrinks; save is full UTF-8; Source insert+undo works with a host window. macOS MarkusTests passed. Viable for v1 with remaining polish: fragment-based hide, caret in collapsed ranges, Preview is styled source not rendered GFM.

### 2026-08-15
T04: MarkusTests passed on iPhone 17 and iPad Pro 13-inch (M5). iOS insertTextAtCaret uses UIKeyInput.insertText (UITextView.shouldChangeText takes UITextRange, not NSRange). Ticket left in-progress for controller review.

## Review

- **Date:** 2026-08-15
- **Verdict:** Important — not done
- **Verify (controller, fresh):** macOS, iPhone 17, and iPad Pro 13-inch (M5) MarkusTests TEST SUCCEEDED.
- **Findings:**
  1. **Important:** Fold hide writes collapsed paragraph styles into `NSTextStorage` (`FoldingTextView.swift` `applyCollapsedParagraphStyles`). The TextKit 2 fragment path (`FoldingTextLayoutFragment`) is unused by stock `NSTextView`/`UITextView`. That is not “exclude folded extents in layout.” Disk save is still full UTF-8 (R5 holds).
  2. **Important:** Tests assert `layoutHeight` drop and `hiddenRangeCount` from the fold store, not actual fragment hide; unfold is untested; Source folded height is compared to unfolded Preview height.
  3. **Minor:** Preview is styled source; `isRichText = false` can fight attribute-based folds.
- **Architecture:** Reopened. Do not start ticket 03 until the hide mechanism is agreed.

### 2026-08-15
Review Important: paragraph-style squash is not layout-exclude. Architecture reopened; ticket not done.

## Notes

### 2026-08-15
Architecture A agreed: own NSTextLayoutManager; T05 fragment hide; no paragraph-style squash.

### 2026-08-15
T05: custom NSView/UIView owns NSTextContentStorage + NSTextLayoutManager + NSTextContainer. textLayoutFragmentFor returns FoldingTextLayoutFragment (isCollapsed, zero height, skip draw). applyCollapsedParagraphStyles removed. packed layout height from non-collapsed fragments. collapsedFragmentCount > 0 after heading+fence fold; unfold restores Source height vs Source unfolded; save full UTF-8; insert+undo in Source. Verify MarkusTests TEST SUCCEEDED: macOS, iPhone 17, iPad Pro 13-inch (M5). Ticket left in-progress.

## Review (T05)

- **Date:** 2026-08-15
- **Verdict:** clean
- **Verify (controller, fresh):** macOS, iPhone 17, iPad Pro 13-inch (M5) MarkusTests TEST SUCCEEDED.
- **Findings:** None. Owns layout manager; fragment hide is live; paragraph-style squash gone. Spike caret and styled-source Preview are in-scope leftovers for later tickets.

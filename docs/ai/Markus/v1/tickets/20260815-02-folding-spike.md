---
id: 20260815-02-folding-spike
title: Folding spike
type: spike
priority: high
status: in-progress
created: 2026-08-15
updated: 2026-08-15
closed:
notes: ''
parent:
depends_on:
- 20260815-01-multiplatform-scaffold
subtasks:
- id: S1
  title: Block index with fold extents
  status: todo
- id: S2
  title: Fold store + full-buffer save
  status: todo
- id: S3
  title: TextKit 2 hide folds in Source and Preview
  status: todo
- id: S4
  title: Three-destination verify
  status: todo
plan_status: done
---
## Description

Parse a file with cmark-gfm, build the block index, custom TextKit 2 view
hides heading and fence fold extents in Preview and Source, shared fold
state, save writes the full buffer. This ticket *is* the editor-view
decision; if it is janky, stop and reopen design.

## Acceptance criteria

- [ ] Block index from cmark-gfm: ATX headings and fenced code blocks with source byte/line ranges
- [ ] Fold/unfold a heading section and a fenced block in Preview and Source
- [ ] Fold state is shared across the mode switch
- [ ] Save writes the complete unfolded source
- [ ] Caret/undo still work in Source after a fold (spike-quality, not polish)
- [ ] Tests pass on Mac, iPhone simulator, and iPad simulator

## Context

Requirements R4, R5, N3. Architecture: one TextKit 2 view, Swift block
index. Hard gate for v1. Parser lives in `Markus/Markus/Markdown/MarkdownParser.swift`.

## Subtasks

- [ ] Block index
- [ ] TextKit 2 fold layout in both modes
- [ ] Shared fold store + full-buffer save
- [ ] Three-destination verify

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
## Notes

### 2026-08-15
T01: Block index reports ATX/fence byte+line ranges and fold extents (heading through next same-or-higher; fence body after opener). macOS MarkusTests passed.

### 2026-08-15
T02: FoldStore is shared across Source/Preview; DocumentSave.writeUTF8 writes full NSTextStorage UTF-8 including folded extents. macOS MarkusTests passed.

### 2026-08-15
T03: TextKit 2 view hides heading/fence extents in Source and Preview via collapsed paragraph styles on the full NSTextStorage (characters unchanged). NSTextLayoutFragment subclass was not invoked by NSTextView; layout still shrinks; save is full UTF-8; Source insert+undo works with a host window. macOS MarkusTests passed. Viable for v1 with remaining polish: fragment-based hide, caret in collapsed ranges, Preview is styled source not rendered GFM.

### 2026-08-15
T04: MarkusTests passed on iPhone 17 and iPad Pro 13-inch (M5). iOS insertTextAtCaret uses UIKeyInput.insertText (UITextView.shouldChangeText takes UITextRange, not NSRange). Ticket left in-progress for controller review.

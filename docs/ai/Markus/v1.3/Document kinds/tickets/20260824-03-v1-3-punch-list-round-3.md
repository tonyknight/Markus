---
id: 20260824-03-v1-3-punch-list-round-3
title: v1.3 punch list round 3
type: bug
priority: high
status: in-progress
created: 2026-08-24
updated: 2026-08-24
closed:
notes: Settings at launch; Markdown New caret; HTML Preview assets; Swift perf
parent:
depends_on: []
subtasks:
- id: T01
  title: Settings must not open at launch
  status: todo
- id: T02
  title: New Markdown opens Source with caret
  status: todo
- id: T03
  title: HTML Preview loads CSS JS images
  status: todo
- id: T04
  title: Swift open fold scroll performance
  status: todo
plan_status: approved
current_task: T01
---
## Description

Third punch list after visual testing of 20260824-02. Launch presents Settings next to the untitled document. File → New Markdown still has no caret (other kinds work). HTML Preview blocks linked CSS/JS/images. Opening, folding, and scrolling Swift files is painfully slow on an M3 Max.

## Acceptance criteria

- [ ] Launching Markus shows the untitled document only. Settings stays closed until gear / Markus → Settings… / ⌘,.
- [ ] File → New → Markdown (Create) opens Source with a blinking caret; typing inserts. Other kinds stay as they are.
- [ ] HTML Preview loads linked CSS, JavaScript, and images (relative to the document file, plus http/https). Top-level link clicks still do not navigate away. SVG Preview stays script-off.
- [ ] A typical Swift source file (thousands of lines) opens, folds, and scrolls without multi-second hitching. Drawing and layout height must not re-walk the full document every frame.

## Context

Worktree: `.worktrees/v1.3-punch-list-3` on `bora/markus-v1-3-punch-list-3`. Origin: `main`. NO TDD. Gate is xcodebuild Debug build.

Issue 9: `MarkusApp` hosts Settings as a SwiftUI `Window` (needed for resize handles). That scene is the only SwiftUI window, so it opens at launch and restores. `defaultLaunchBehavior(.suppressed)` (macOS 15+) plus `isRestorable = false` and a launch close on macOS 14.

Issue 10: `DocumentSession.applyKind` forces Source for every non-Markdown kind. Untitled Markdown keeps `EditorSettings.loadDefaultMode()`, which defaults to Preview. `becomeKeyEditorIfNeeded` and typing only run in Source. Fix: untitled documents always open Source (`applyUntitledKind`).

Issue 11: Product override of N5 for HTML Preview. Round 2 kept JS off, `baseURL` nil, and a blanket subresource blocker — that is why CSS/JS/images never load. Enable JS for HTML, set `baseURL` to the document directory when we have a file URL, allow http/https/file/data subresources, still cancel `.linkActivated` and popups. SVG stays locked (no script).

Issue 12: `drawGutter` uses `layoutHeight` every frame; `packedLayoutHeight()` enumerates every TextKit fragment with `.ensuresLayout`. `ensureLayout()` layouts the whole document on fold. `applyCodeHighlightSpans` copies the entire attributed string. Cache packed height, fill only the visible gutter, layout the visible range, highlight in place.

## Subtasks

- [ ] T01 Settings must not open at launch.
- [ ] T02 New Markdown opens Source with caret.
- [ ] T03 HTML Preview loads CSS, JS, and images.
- [ ] T04 Swift open/fold/scroll performance.

## Implementation plan

Status: approved
Current task: T01

### T01: Settings must not open at launch

Suppress the Settings `Window` at launch (`defaultLaunchBehavior(.suppressed)` when available). Mark the NSWindow non-restorable. On macOS 14, close an unsolicited Settings window at the end of `applicationDidFinishLaunching`. Gear / menu / ⌘, still open it.

Files: `Markus/Markus/MarkusApp.swift`, `Markus/Markus/Document/SettingsWindow.swift`, `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [ ] done

### T02: New Markdown opens Source with caret

`applyUntitledKind` sets mode to Source after kind assignment so File → New Markdown (and launch untitled) is editable. `becomeKeyEditorIfNeeded` already runs in Source. Opening an existing `.md` still honors the Editor default mode.

Files: `Markus/Markus/Document/MarkdownDocument.swift`, `Markus/Markus/Document/DocumentSession.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [ ] done

### T03: HTML Preview loads CSS, JS, and images

Product override of N5 for HTML: `allowsContentJavaScript = true`, `loadHTMLString` with `baseURL` = document directory when the file exists, drop the blanket subresource content blocker for HTML, allow http/https/file/data in the navigation delegate for non-linkActivated loads. Keep cancelling link clicks, forms, and `createWebView`. SVG stays script-off with `baseURL` nil.

Files: `Markus/Markus/Preview/LockedHTMLPreview.swift`, `Markus/Markus/ContentView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] done

### T04: Swift open/fold/scroll performance

Stop calling `packedLayoutHeight()` from the per-frame gutter draw (fill the visible rect only). Cache packed height and invalidate on text/fold/width. `ensureLayout` must not force layout of the whole document on every fold. Apply code highlight spans in-place on `NSTextStorage` (no full attributed-string copy).

Files: `Markus/Markus/Editor/FoldingTextView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] done

## Notes

- 2026-08-24: Ticket created. Worktree `.worktrees/v1.3-punch-list-3`, branch `bora/markus-v1-3-punch-list-3`.

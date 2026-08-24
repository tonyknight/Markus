---
id: 20260824-03-v1-3-punch-list-round-3
title: v1.3 punch list round 3
type: bug
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: T01–T04 implemented; Settings launch, Markdown caret, HTML assets, Swift perf
parent:
depends_on: []
subtasks:
- id: T01
  title: Settings must not open at launch
  status: done
- id: T02
  title: New Markdown opens Source with caret
  status: done
- id: T03
  title: HTML Preview loads CSS JS images
  status: done
- id: T04
  title: Swift open fold scroll performance
  status: done
plan_status: done
current_task: T04
---
## Description

Third punch list after visual testing of 20260824-02. Launch presents Settings next to the untitled document. File → New Markdown still has no caret (other kinds work). HTML Preview blocks linked CSS/JS/images. Opening, folding, and scrolling Swift files is painfully slow on an M3 Max.

## Acceptance criteria

- [x] Launching Markus shows the untitled document only. Settings stays closed until gear / Markus → Settings… / ⌘,.
- [x] File → New → Markdown (Create) opens Source with a blinking caret; typing inserts. Other kinds stay as they are.
- [x] HTML Preview loads linked CSS, JavaScript, and images (relative to the document file, plus http/https). Top-level link clicks still do not navigate away. SVG Preview stays script-off.
- [x] A typical Swift source file (thousands of lines) opens, folds, and scrolls without multi-second hitching. Drawing and layout height must not re-walk the full document every frame.

## Context

Worktree: `.worktrees/v1.3-punch-list-3` on `bora/markus-v1-3-punch-list-3`. Origin: `main`. NO TDD. Gate is xcodebuild Debug build.

Issue 9: `MarkusApp` hosts Settings as a SwiftUI `Window` (needed for resize handles). That scene is the only SwiftUI window, so it opens at launch and restores. `defaultLaunchBehavior(.suppressed)` does not compose in `SceneBuilder` (control-flow error). Fix: `isRestorable = false` plus close unsolicited Settings windows at launch.

Issue 10: `DocumentSession.applyKind` forces Source for every non-Markdown kind. Untitled Markdown keeps `EditorSettings.loadDefaultMode()`, which defaults to Preview. `becomeKeyEditorIfNeeded` and typing only run in Source. Fix: untitled documents always open Source (`applyUntitledKind`).

Issue 11: Product override of N5 for HTML Preview. Round 2 kept JS off, `baseURL` nil, and a blanket subresource blocker — that is why CSS/JS/images never load. Enable JS for HTML, set `baseURL` to the document directory when we have a file URL, allow http/https/file/data subresources, still cancel `.linkActivated` and popups. SVG stays locked (no script).

Issue 12: `drawGutter` uses `layoutHeight` every frame; `packedLayoutHeight()` enumerates every TextKit fragment with `.ensuresLayout`. `ensureLayout()` layouts the whole document on fold. `applyCodeHighlightSpans` copies the entire attributed string. Cache packed height, fill only the visible gutter, skip full-document ensureLayout, highlight in place.

## Subtasks

- [x] T01 Settings must not open at launch.
- [x] T02 New Markdown opens Source with caret.
- [x] T03 HTML Preview loads CSS, JS, and images.
- [x] T04 Swift open/fold/scroll performance.

## Implementation plan

Status: done
Current task: T04

### T01: Settings must not open at launch

Close unsolicited Settings windows at launch. Mark the NSWindow non-restorable. Gear / menu / ⌘, still open it.

Files: `Markus/Markus/MarkusApp.swift`, `Markus/Markus/Document/SettingsWindow.swift`, `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T02: New Markdown opens Source with caret

`applyUntitledKind` sets mode to Source after kind assignment so File → New Markdown (and launch untitled) is editable. Opening an existing `.md` still honors the Editor default mode.

Files: `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T03: HTML Preview loads CSS, JS, and images

Product override of N5 for HTML: JS on, `baseURL` = document directory, no blanket blocker on HTML, allow http/https/file/data subresources. Cancel link clicks, forms, popups. SVG stays script-off.

Files: `Markus/Markus/Preview/LockedHTMLPreview.swift`, `Markus/Markus/ContentView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

### T04: Swift open/fold/scroll performance

Stop calling `packedLayoutHeight()` from the per-frame gutter draw. Cache packed height. `ensureLayout` must not force layout of the whole document on every fold. Apply code highlight spans in-place.

Files: `Markus/Markus/Editor/FoldingTextView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

## Notes

- 2026-08-24: Ticket created. Worktree `.worktrees/v1.3-punch-list-3`, branch `bora/markus-v1-3-punch-list-3`.
- 2026-08-24 T01: Close unsolicited Settings at launch; `isRestorable = false`. macOS Debug BUILD SUCCEEDED.
- 2026-08-24 T02: Untitled documents force Source. macOS Debug BUILD SUCCEEDED.
- 2026-08-24 T03: HTML Preview loads CSS/JS/images; SVG stays locked. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED.
- 2026-08-24 T04: Cached packed height, visible gutter fill, in-place highlights, no full-document ensureLayout on fold. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED.

## Review

2026-08-24. Verdict: **minors only**.

Commits T01–T04 on `bora/markus-v1-3-punch-list-3`. Spec matches: Settings is closed at launch; untitled Markdown is Source; HTML Preview can fetch subresources; Swift layout work is no longer per-frame full-document.

- Minor: `defaultLaunchBehavior(.suppressed)` could not be applied in `SceneBuilder` (control-flow error). Launch close + non-restorable window is the shipped fix.
- Minor: HTML Preview can run page script and load http(s) — explicit product override of N5. Link clicks and popups still cancelled. Sibling files in the sandbox still need directory access (Open Folder or the opened file’s directory).
- Minor: Minimap snapshots can still walk packed height once on document change; scroll/gutter no longer do that every frame.

No Critical or Important. Ticket can close.

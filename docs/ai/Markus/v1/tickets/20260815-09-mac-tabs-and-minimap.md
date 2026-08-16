---
id: 20260815-09-mac-tabs-and-minimap
title: Mac tabs and minimap
type: feature
priority: medium
status: done
created: 2026-08-15
updated: 2026-08-16
closed: 2026-08-16
notes: T05 review minors-only; marking done
parent:
depends_on:
- 20260815-08-theme-picker
subtasks:
- id: S1
  title: NSDocument tabbing
  status: done
- id: S2
  title: Fold-aware minimap
  status: done
- id: S3
  title: Confirm iOS has no tabs/minimap
  status: done
- id: S4
  title: Verify
  status: done
- id: S5
  title: Mac document scene and open-as-tab
  status: done
plan_status: done
---
## Description

Tabbed `NSDocument` windows. Minimap of the current mode that hides or
compresses folds. Not on iPhone; not required on iPad.

## Acceptance criteria

- [x] Mac can have multiple documents in tabs
- [x] Minimap shows the current mode and hides or compresses folded ranges
- [x] iPhone has neither tabs nor minimap
- [x] iPad has no tabs; minimap not required
- [x] macOS tests pass (shared editor tests still pass on iOS destinations)

## Context

Requirements R10, R11. Mac-only chrome.

## Subtasks

- [x] NSDocument tabbing
- [x] Fold-aware minimap
- [x] Confirm iOS has no tabs/minimap
- [x] Verify

## Implementation plan

Status: done
Current task: 

### T01: Mac NSDocument tabbing
On **macOS**, documents are **NSDocument** windows with **tabbing** (architecture: NSDocument + tabbed windows). Reuse existing `DocumentSession` / `FoldingTextView` inside the document window — do not invent a second editor. Enable automatic tabbing (`tabbingMode` preferred / equivalent). iOS/iPad stay one document via the existing SwiftUI `WindowGroup` (switch via tree/recents). Tests: Mac document type exists and prefers tabs; opening a second document does not require a fake SwiftUI tab bar. Do not add a minimap yet.
Files: `MarkusApp.swift`, Mac `NSDocument` (or DocumentGroup hosting NSDocument), tests under `#if os(macOS)`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T02: Fold-aware minimap
Mac-only minimap of the **current mode** (Preview or Source styling of the same buffer). Folded ranges are **hidden or compressed** using the packed `SourceLineMap` (same Y packing as fold hide). Clicking a minimap Y maps to `sourceLine(atY:)` / scroll if already available; if scroll is not wired, at least the map omits folded extents. Not on iPhone; not required on iPad. Tests: after folding a heading, minimap height shrinks or those source lines are omitted; unfold restores. Do not squash paragraph styles.
Files: `Markus/Markus/Editor/` Mac minimap view, tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T03: iPhone/iPad have no tabs or required minimap
Compile-time / API flags: tabs and minimap are **macOS only**. Tests on iOS: no NSDocument tabbing surface; no minimap view in the iOS chrome. Shared editor tests still pass.
Files: chrome flags + tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T04: Three-destination verify
Mac-only chrome still runs shared tests on iOS.
Verify:
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
(also re-run macOS)
Files: tests as needed; no editor QoL (ticket 10)
- [ ] todo
- [x] done

### T05: Mac document scene and open-as-tab
Fix Critical/Important review:
1. Mac SwiftUI app must **host NSDocument windows** on the launch/open path (not a Settings-only scene). `NSDocumentController` opens untitled and file URLs; `makeWindowControllers()` is actually used. Tests must create a document and prove a window controller exists (not only `tabbingMode` flags).
2. Opening a **second** file on Mac (Open / Recents / Finder) creates another `MarkdownDocument` **tab**, not `host.openPicked` replacing the current session. Folder-tree child files may still replace inside the folder session. iOS stays one session.
3. Untitled / `read(from data:)` must show the editor (set `fileURL` or otherwise not gate the editor on a nil URL). Minimap appears when the editor is shown.
4. NSDocument save and `DocumentSession` dirty/`lastSavedText` stay in sync (`updateChangeCount` or session save after AppKit write).
Files: `MarkusApp.swift`, `MarkdownDocument.swift`, `ContentView.swift` / `DocumentHost.swift` as needed, Mac tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
then iPhone 17 and iPad Pro 13-inch (M5) same as T04.
- [ ] todo
- [x] done

## Notes

### 2026-08-16
T01: Mac NSDocument tabbing with preferred tabbingMode; iOS stays WindowGroup. SHA 28fad93. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-16
T02: Mac minimap uses SourceLineMap packed Y; folds omit/compress height. SHA 53a6b81. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-16
T03: MacOnlyChrome flags — tabs/minimap macOS only, iOS neither. SHA 32d5b86. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-16
T04: MarkusTests TEST SUCCEEDED on iPhone 17, iPad Pro 13-inch (M5), and macOS. No code changes. Ticket remains in-progress (not marked done).

## Review

- **Date:** 2026-08-16
- **Verdict:** Critical — not done
- **Verify (controller, fresh):** MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5) (flag/snapshot tests only).
- **Findings:**
  1. **Critical:** Mac SwiftUI app is Settings-only; nothing creates `MarkdownDocument` windows on launch/open.
  2. **Important:** In-app Open/Recents/tree replace one `DocumentHost` session instead of opening another NSDocument tab.
  3. **Important:** Editor/minimap stay hidden until `session.fileURL` is set; untitled/`read(from data:)` never sets it.
  4. **Important:** NSDocument `write(to:)` does not update session dirty/`lastSavedText`.
  5. **Minor:** Minimap is gray bars not token-styled; click-to-scroll unhooked; per-window ThemeStore.

### 2026-08-16
Review Critical: Mac document scene and open-as-tab. T05.

### 2026-08-16
T05: Mac NSDocumentController launch/open, chrome open-as-tab, untitled editor, write clears dirty. SHA 2f77d56. MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5). Ticket remains in-progress.

## Review (T05)

- **Date:** 2026-08-16
- **Verdict:** Minor only — done
- **Verify (controller, fresh):** MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5).
- **Findings:**
  1. **Minor:** Second-open test asserts the first session was not replaced, not a second window controller.
  2. **Minor:** SwiftUI scene list is still Settings-only; documents are AppKit NSDocument.
  3. **Minor (carry-over):** Minimap is gray bars; click-to-scroll unhooked; per-window ThemeStore; typing may not `updateChangeCount(.changeDone)`.

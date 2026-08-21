---
id: 20260820-01-settings-window-and-navigation
title: Settings window and navigation
type: feature
priority: high
status: in-progress
created: 2026-08-20
updated: 2026-08-20
closed:
notes: 'model_tier: premium'
parent:
depends_on: []
subtasks:
- id: T1
  title: SwiftUI Settings scene with sidebar (Appearance, Editor, About placeholders)
  status: todo
- id: T2
  title: Wire gear, Markus → Settings…, and ⌘, to this window
  status: todo
- id: T3
  title: Remove the stub Settings scene copy
  status: todo
plan_status: in-progress
current_task: T02
---
## Description

macOS Settings is still a stub scene (“Open a Markdown document to edit.”) plus an in-window takeover. This ticket creates the real Settings **window**: a SwiftUI `Settings` scene so ⌘, works, with a left category list (Appearance, Editor, About) and a right detail pane. Appearance/Editor/About may be placeholders. The gear must open this same window.

If `Settings` + `NavigationSplitView` cannot host the later Appearance inner split, fall back to an app-owned `NSWindow` that ⌘, still opens — same IA (Requirements risk note). Do not swap `ContentView` for Settings here; ticket 02 removes the takeover.

## Acceptance criteria

- [ ] A Settings window exists with a left list of Appearance, Editor, and About, and a right detail pane (R1).
- [ ] Ribbon gear, **Markus → Settings…**, and ⌘, all open that same window (R2).
- [ ] The stub `Settings { Text("Open a Markdown document to edit.") }` is gone (R2).
- [ ] macOS Debug build succeeds.

## Context

- Requirements: R1, R2. Architecture components 1–2.
- Planning: `(2026-08-20) v1.2.md` §A.
- Today: `MarkusApp.swift` Settings stub; `RibbonRail` / `DocumentHost.presentSettings()`; `ContentView` swaps to `SettingsScene`.
- Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`

## Routing

**Tier: premium.** New window host, system Settings vs custom `NSWindow` fallback, three entry points that must not diverge. Matches `bora-plan` / hard chrome work, not economy verify.

## Subtasks

- [ ] Host the Warp-style split in the macOS `Settings` scene (or documented NSWindow fallback).
- [ ] Sidebar: Appearance, Editor, About (placeholder detail is fine).
- [ ] Gear, app Settings menu, and ⌘, open this window.
- [ ] Delete the stub Settings copy.

## Implementation plan

Status: in-progress
Current task: T02

### T01: Settings window view with sidebar

Add a macOS-only SwiftUI root for the Preferences window: left list of Appearance, Editor, and About; right pane a placeholder for the selected category. Use a non-collapsing `HStack` + sidebar `List` (same split as today's in-window `SettingsScene`) inside the SwiftUI `Settings` scene rather than `NavigationSplitView`, because component 1 requires the sidebar not to collapse. Do not wire it yet — `MarkusApp` still hosts the stub so this commit is the view only.

Files: `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

### T02: Host the split in the Settings scene (delete stub)

Replace `Settings { Text("Open a Markdown document to edit.") }` in `MarkusApp` with `SettingsWindowView`. SwiftUI's `Settings` scene already installs **Markus → Settings…** and ⌘,; those entry points now open this window. Give the scene a default size that can later hold the Appearance inner split. Leave `ContentView`'s `SettingsScene` takeover untouched.

Files: `Markus/Markus/MarkusApp.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [ ] todo

### T03: Gear opens the Settings window

Change the ribbon gear from `host.presentSettings()` (viewport swap) to `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` so it opens the same Settings window as the menu and ⌘,. Do not remove `isSettingsPresented` / `ContentView` → `SettingsScene` (ticket 02). Leave `DocumentHost.presentSettings()` as the takeover API.

Files: `Markus/Markus/Document/RibbonRail.swift`, `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [ ] todo

## Notes

Append-only running log. Each entry dated.

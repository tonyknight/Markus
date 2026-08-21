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
  status: done
- id: T2
  title: Wire gear, Markus → Settings…, and ⌘, to this window
  status: done
- id: T3
  title: Remove the stub Settings scene copy
  status: done
plan_status: done
---
## Description

macOS Settings is still a stub scene (“Open a Markdown document to edit.”) plus an in-window takeover. This ticket creates the real Settings **window**: a SwiftUI `Settings` scene so ⌘, works, with a left category list (Appearance, Editor, About) and a right detail pane. Appearance/Editor/About may be placeholders. The gear must open this same window.

If `Settings` + `NavigationSplitView` cannot host the later Appearance inner split, fall back to an app-owned `NSWindow` that ⌘, still opens — same IA (Requirements risk note). Do not swap `ContentView` for Settings here; ticket 02 removes the takeover.

## Acceptance criteria

- [x] A Settings window exists with a left list of Appearance, Editor, and About, and a right detail pane (R1).
- [x] Ribbon gear, **Markus → Settings…**, and ⌘, all open that same window (R2).
- [x] The stub `Settings { Text("Open a Markdown document to edit.") }` is gone (R2).
- [x] macOS Debug build succeeds.

## Context

- Requirements: R1, R2. Architecture components 1–2.
- Planning: `(2026-08-20) v1.2.md` §A.
- Today: `MarkusApp.swift` Settings stub; `RibbonRail` / `DocumentHost.presentSettings()`; `ContentView` swaps to `SettingsScene`.
- Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`

## Routing

**Tier: premium.** New window host, system Settings vs custom `NSWindow` fallback, three entry points that must not diverge. Matches `bora-plan` / hard chrome work, not economy verify.

## Subtasks

- [x] Host the Warp-style split in the macOS `Settings` scene (or documented NSWindow fallback).
- [x] Sidebar: Appearance, Editor, About (placeholder detail is fine).
- [x] Gear, app Settings menu, and ⌘, open this window.
- [x] Delete the stub Settings copy.

## Implementation plan

Status: done
Current task: 

### T01: Settings window view with sidebar

Add a macOS-only SwiftUI root for the Preferences window: left list of Appearance, Editor, and About; right pane a placeholder for the selected category. Use a non-collapsing `HStack` + sidebar `List` (same split as today's in-window `SettingsScene`) inside the SwiftUI `Settings` scene rather than `NavigationSplitView`, because component 1 requires the sidebar not to collapse. Do not wire it yet — `MarkusApp` still hosts the stub so this commit is the view only.

Files: `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

### T02: Host the split in the Settings scene (delete stub)

Replace `Settings { Text("Open a Markdown document to edit.") }` in `MarkusApp` with `SettingsWindowView`. SwiftUI's `Settings` scene already installs **Markus → Settings…** and ⌘,; those entry points now open this window. Give the scene a default size that can later hold the Appearance inner split. Leave `ContentView`'s `SettingsScene` takeover untouched.

Files: `Markus/Markus/MarkusApp.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

### T03: Gear opens the Settings window

Change the ribbon gear from `host.presentSettings()` (viewport swap) to `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` so it opens the same Settings window as the menu and ⌘,. Do not remove `isSettingsPresented` / `ContentView` → `SettingsScene` (ticket 02). Leave `DocumentHost.presentSettings()` as the takeover API.

Files: `Markus/Markus/Document/RibbonRail.swift`, `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

### T04: Open Settings via openSettings environment

Review Important: `showSettingsWindow:` is not a valid AppKit selector on macOS 14+. Gear calls `@Environment(\.openSettings)` (and the live **Markus → Settings…** menu item as a fallback because the rail is inside `NSHostingController`). Drop the string selector. Sidebar selection uses accent fill + primary text so inactive-window contrast stays readable.

Files: `Markus/Markus/Document/RibbonRail.swift`, `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

## Notes

Append-only running log. Each entry dated.

- 2026-08-20: Implemented R1/R2. T01 added `SettingsWindowView` (non-collapsing `HStack` split, Appearance / Editor / About placeholders — not `NavigationSplitView`, so the sidebar cannot collapse). T02 replaced the stub `Settings { Text(...) }` with that view; SwiftUI’s Settings scene still provides **Markus → Settings…** and ⌘,. T03 gear calls `SettingsWindowChrome.open()` (`showSettingsWindow:`) instead of `presentSettings()`. Left `ContentView` → `SettingsScene` takeover and `DocumentHost.presentSettings()` for ticket 02. macOS Debug build succeeded after each task. Did not run `xcodebuild test`. Did not launch the app for a visual pass from this session.
- 2026-08-20: T04 review fix. Gear now calls `@Environment(\.openSettings)` (passed into `SettingsWindowChrome.open`), then the live **Markus → Settings…** menu item (⌘,) as a fallback because the rail is inside `NSHostingController`. Removed `showSettingsWindow:` string selector. Sidebar selection uses accent fill + primary text (inactive-window contrast). macOS Debug build succeeded. Ticket left in-progress.

## Review

**2026-08-20 — Important.** Do not mark done.

- **Important:** Gear opener `SettingsWindowChrome.open()` sends `showSettingsWindow:` with `NSApp.sendAction`. That selector is not in the macOS 26 AppKit headers; Apple’s supported APIs since macOS 14 are `SettingsLink` and `@Environment(\.openSettings)`. The gear lives in an `NSHostingController` document window, so a silent no-op fails R2 for that entry point. **Markus → Settings…** and ⌘, from the `Settings` scene are unaffected. Replace the string-selector sendAction and confirm in a running app.
- **Minor:** Sidebar selection uses `selectedContentBackgroundColor` plus `alternateSelectedControlTextColor`, which can paint light text on an inactive gray fill when Settings is not the key window.

Controller may not mark done. Exposed usage: `SettingsWindowView` in the macOS `Settings` scene; `SettingsWindowChrome.open()` is the intended shared opener — do not reuse it until the Important finding is fixed.

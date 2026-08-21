---
id: 20260820-02-retire-in-document-settings-takeover
title: Retire in-document settings takeover
type: feature
priority: high
status: done
created: 2026-08-20
updated: 2026-08-20
closed: 2026-08-20
notes: 'model_tier: standard'
parent:
depends_on:
- 20260820-01-settings-window-and-navigation
subtasks:
- id: T1
  title: Stop swapping ContentView to SettingsScene on macOS
  status: done
- id: T2
  title: Confirm the document editor stays mounted while Settings is open
  status: done
plan_status: done
---
## Description

v1.1 presents Settings by replacing the document viewport (`ContentView` → `SettingsScene`). That tears down the editor and is why focus/scroll bugs appear on close. Once ticket 01 owns a real Settings window, this ticket removes the takeover. `isSettingsPresented` on macOS must not unmount the editor.

## Acceptance criteria

- [x] Opening Settings does not replace the document viewport (R1, R12).
- [x] Closing Settings does not rebuild the document editor (R12).
- [x] macOS Debug build succeeds.

## Context

- Requirements: R1, R12. Depends on 20260820-01.
- `ContentView.swift` macOS branch `if host.isSettingsPresented { SettingsScene }`.
- Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- After the build: launch, open a file, open Settings, confirm the document is still there.

## Routing

**Tier: standard.** Mechanical removal once the new window exists. Reasoning is localized; catalog standard aliases are enough.

## Subtasks

- [x] Remove the macOS `ContentView` swap to `SettingsScene`.
- [x] Gear still opens the ticket-01 window, not a viewport flag.
- [x] iOS sheet unchanged (R13).

## Implementation plan

Status: done
Current task: 

### T01: Stop swapping ContentView to SettingsScene on macOS

Remove the macOS `if host.isSettingsPresented { SettingsScene } else { documentScene }` branch so `ContentView.body` always hosts `documentScene`. Opening the ticket-01 Settings window must not replace the document viewport. Leave `SettingsScene.swift` in the tree for T02. Leave the iOS sheet (`SettingsSheetModifier` / `SettingsPane` / `host.isSettingsPresented`) unchanged. Gear already calls `SettingsWindowChrome.open` via `@Environment(\.openSettings)` — do not retarget it to `presentSettings()`.

Files: `Markus/Markus/ContentView.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

### T02: Confirm the document editor stays mounted while Settings is open

With `documentScene` always mounted, delete the unused in-window takeover (`SettingsScene`, `SettingsCategory`, `SettingsChrome`) and `SettingsSceneTests`. Remove the `SessionEditorRepresentable.updateNSView` first-responder reclaim that existed only to recover focus after Settings tore down the editor. Update leftover comments that still describe the takeover (`RibbonRail.swift`, `SettingsWindow.swift`). Keep `DocumentHost.presentSettings()` and `isSettingsPresented` for the iOS sheet.

Files: `Markus/Markus/ContentView.swift`, `Markus/Markus/Document/SettingsScene.swift` (delete), `Markus/MarkusTests/SettingsSceneTests.swift` (delete), `Markus/Markus/Document/RibbonRail.swift`, `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-20
T01: ContentView.body always hosts documentScene on macOS; SettingsScene swap removed. iOS sheet and presentSettings() unchanged. Gear still uses SettingsWindowChrome.open. macOS Debug BUILD SUCCEEDED.

### 2026-08-20
T02: Deleted SettingsScene/SettingsCategory/SettingsChrome and SettingsSceneTests. Removed SessionEditorRepresentable first-responder reclaim (that recovered focus after the swap remounted the editor). Gear comments updated. iOS sheet and presentSettings() kept. macOS Debug BUILD SUCCEEDED. Ticket left in-progress.

## Review

2026-08-20 — **Minor.** Controller may mark done.

R1/R12: `ContentView.body` always hosts `documentScene`. `SettingsScene` deleted. iOS sheet kept (`SettingsSheetModifier`). Gear still `SettingsWindowChrome.open`. Commits `eb7d8bb`, `80e94ff` match the plan.

Minor: `presentSettings()` remains for iOS only, as specified.

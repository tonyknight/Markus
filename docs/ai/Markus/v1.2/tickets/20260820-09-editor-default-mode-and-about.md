---
id: 20260820-09-editor-default-mode-and-about
title: Editor default mode and About
type: feature
priority: medium
status: done
created: 2026-08-20
updated: 2026-08-20
closed: 2026-08-20
notes: 'model_tier: economy'
parent:
depends_on:
- 20260820-01-settings-window-and-navigation
subtasks:
- id: T1
  title: Persist default open mode (Preview / Source) for new and newly opened documents
  status: done
- id: T2
  title: About page shows app name and short version from the bundle
  status: done
plan_status: done
---
## Description

Fill the two thin Settings categories. **Editor:** default open mode Preview (default) or Source, persisted, applied to untitled and newly opened documents — not to windows already open. **About:** app name and short version from the bundle. No other Editor settings.

## Acceptance criteria

- [x] Editor page sets default Preview or Source; new/opened documents honor it (R10).
- [x] About shows app name and version (R11).
- [x] macOS Debug build succeeds. Open both pages by eye.

## Context

- Requirements: R10, R11. Depends on 01 (sidebar hosts the pages).
- Verify: macOS Debug build + launch Settings.

## Routing

**Tier: economy.** Form controls and bundle strings. No new architecture. This host may not have economy catalog models — see routing resolve; ASK if unmatched.

## Subtasks

- [x] Persist and apply default mode on open/untitled.
- [x] About: `CFBundleName` / `CFBundleShortVersionString` (or equivalent).

## Implementation plan

Status: done
Current task:

### T01: Persist default open mode for new and newly opened documents

Add `EditorSettings` with `defaultModeKey = "markus.editor.defaultMode"`, `loadDefaultMode(from:)`, and `saveDefaultMode(_:to:)`. Conform `EditorMode` to `String, CaseIterable, Codable`. Use `EditorSettings.loadDefaultMode()` as default `mode` in `FoldingTextView.init`. Implement `EditorSettingsView` with a Picker in `SettingsWindow.swift` and wire it into `SettingsWindowDetail` for `.editor`. Persisted in `UserDefaults`, applied to untitled and newly opened documents, without mutating windows already open.

Files: `Markus/Markus/Document/EditorSettings.swift`, `Markus/Markus/Markdown/FoldStore.swift`, `Markus/Markus/Editor/FoldingTextView.swift`, `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

### T02: About page shows app name and short version from the bundle

Implement `AboutSettingsView` in `SettingsWindow.swift` displaying the app icon, app name (`CFBundleDisplayName` or `CFBundleName`), and short version string (`CFBundleShortVersionString`). Wire it into `SettingsWindowDetail` for `.about`.

Files: `Markus/Markus/Document/SettingsWindow.swift`

Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- [x] done

## Notes

Append-only running log. Each entry dated.

- 2026-08-20: T01 done. Created `EditorSettings` with `loadDefaultMode`/`saveDefaultMode` backed by `UserDefaults` (`markus.editor.defaultMode`). Extended `EditorMode` with `String`, `CaseIterable`, and `Codable`. Updated `FoldingTextView` default `mode` to read `EditorSettings.loadDefaultMode()`. Added `EditorSettingsView` in `SettingsWindow.swift` with radio-group picker and wired it into `SettingsWindowDetail` for the `.editor` category. Verified macOS Debug build succeeded.
- 2026-08-20: T02 done. Added `AboutSettingsView` in `SettingsWindow.swift` displaying the app icon, bundle app name (`CFBundleDisplayName` / `CFBundleName`), and short version string (`CFBundleShortVersionString`). Wired it into `SettingsWindowDetail` for `.about`. Verified macOS Debug build succeeded.

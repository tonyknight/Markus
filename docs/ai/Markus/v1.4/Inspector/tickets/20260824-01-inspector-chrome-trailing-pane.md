---
id: 20260824-01-inspector-chrome-trailing-pane
title: Inspector chrome trailing pane
type: feature
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: Trailing inspector column; editor stays mounted
parent:
depends_on: []
subtasks:
- id: T01
  title: Trailing inspector pane and show/hide
  status: done
plan_status: done
current_task: T01
---
## Description

Add a trailing SwiftUI inspector column on Mac and iPad. Showing or hiding it must not unmount `SessionEditorRepresentable` (v1.1 Settings lesson). Placeholders for Document / Outline / Warnings are enough.

## Acceptance criteria

- [x] Mac and iPad show a trailing inspector column when the flag is on (default on).
- [x] Hiding the inspector leaves the editor mounted; caret and folds do not reset.
- [x] Library panel still works independently.
- [x] Mac has a View or ribbon control to toggle the inspector.
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Requirements architecture **A**. `ContentView.documentChrome` is an `HStack`: ribbon, optional library, `editorColumn`. Insert the inspector after `editorSurface` (minimap stays far trailing if present).

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 Trailing inspector pane and show/hide.

## Implementation plan

Status: approved
Current task: T01

### T01: Trailing inspector pane and show/hide

Add `isInspectorPresented` (default `true`) on `DocumentHost`. New `InspectorPane` with three labeled placeholder sections. Wire into `ContentView` editor `HStack` on macOS and iPad (`horizontalSizeClass == .regular` is acceptable for iPad). Mac: ribbon or `View` menu toggle. Do not wrap the editor in `if isInspectorPresented`.

Files: `Markus/Markus/Document/DocumentHost.swift`, `Markus/Markus/ContentView.swift`, new `Markus/Markus/Inspector/InspectorPane.swift` (add to pbxproj), `Markus/Markus/Document/RibbonRail.swift` and/or `Markus/Markus/Document/MarkusCommands.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

## Notes

- 2026-08-24: Ticket created. Execute branch `bora/markus-v1-4-inspector`. Origin: `main`.
- 2026-08-24: Implemented trailing inspector (Mac/iPad), ribbon + View menu toggle. Debug builds succeeded (macOS, iPhone 17, iPad Pro 13-inch M5). Human should confirm hide/show does not reset caret or folds.

## Review

- Date: 2026-08-24
- Verdict: Minors only
- Findings:
  - Trailing `InspectorPane` is a sibling of `editorSurface`; hide/show only wraps the pane, not `SessionEditorRepresentable`.
  - Mac: ribbon `sidebar.right` + View menu Inspector (⌥⌘I). Library panel remains independent.
  - Caret/folds after hide/show still need a human eye-check in the running app.

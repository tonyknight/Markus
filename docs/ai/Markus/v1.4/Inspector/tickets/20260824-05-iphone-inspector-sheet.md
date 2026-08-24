---
id: 20260824-05-iphone-inspector-sheet
title: iPhone inspector sheet
type: feature
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: Same three sections in a sheet; editor stays mounted
parent:
depends_on:
- 20260824-01-inspector-chrome-trailing-pane
- 20260824-02-inspector-document-section
- 20260824-03-inspector-outline-section
- 20260824-04-inspector-warnings-section
subtasks:
- id: T01
  title: iPhone Inspector sheet
  status: done
plan_status: done
current_task: T01
---
## Description

On iPhone, present the same Document / Outline / Warnings content in a sheet. The editor underneath stays mounted. Keep the compact Outline menu.

## Acceptance criteria

- [x] iPhone can open Inspector as a sheet with all three sections.
- [x] Opening/closing the sheet does not unmount `SessionEditorRepresentable`.
- [x] Compact Outline menu remains.
- [x] iPad still uses the trailing column from ticket 01.
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Reuse `InspectorPane` in a `.sheet`. Toolbar or menu item “Inspector”. Do not replace `ContentView`’s root.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 iPhone Inspector sheet.

## Implementation plan

Status: approved
Current task: T01

### T01: iPhone Inspector sheet

On compact width, do not show the trailing column. Add a control that sets a presented flag and sheets `InspectorPane`. iPad regular width keeps the column.

Files: `Markus/Markus/ContentView.swift`, `Markus/Markus/Document/DocumentHost.swift`, `Markus/Markus/Inspector/InspectorPane.swift`

Verify: same three `xcodebuild` Debug builds as ticket 01.
- [x] done

## Notes

- 2026-08-24: Ticket created. Depends on 01–04.
- 2026-08-24: iPhone compact toolbar Inspector sheet; iPad keeps trailing column. Debug builds succeeded. Human should confirm the sheet on iPhone.

## Review

- Date: 2026-08-24
- Verdict: Minors only
- Findings:
  - Compact width: toolbar Inspector opens a sheet with `InspectorPane` and Done. Outline menu kept.
  - iPad regular width still uses the trailing column. Editor stays in `documentScene` under the sheet.

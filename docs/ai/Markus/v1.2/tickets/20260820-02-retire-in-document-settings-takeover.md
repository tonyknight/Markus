---
id: 20260820-02-retire-in-document-settings-takeover
title: Retire in-document settings takeover
type: feature
priority: high
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: standard"
parent:
depends_on:
- 20260820-01-settings-window-and-navigation
subtasks:
- id: T1
  title: Stop swapping ContentView to SettingsScene on macOS
  status: todo
- id: T2
  title: Confirm the document editor stays mounted while Settings is open
  status: todo
---
## Description

v1.1 presents Settings by replacing the document viewport (`ContentView` → `SettingsScene`). That tears down the editor and is why focus/scroll bugs appear on close. Once ticket 01 owns a real Settings window, this ticket removes the takeover. `isSettingsPresented` on macOS must not unmount the editor.

## Acceptance criteria

- [ ] Opening Settings does not replace the document viewport (R1, R12).
- [ ] Closing Settings does not rebuild the document editor (R12).
- [ ] macOS Debug build succeeds.

## Context

- Requirements: R1, R12. Depends on 20260820-01.
- `ContentView.swift` macOS branch `if host.isSettingsPresented { SettingsScene }`.
- Verify: `xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build`
- After the build: launch, open a file, open Settings, confirm the document is still there.

## Routing

**Tier: standard.** Mechanical removal once the new window exists. Reasoning is localized; catalog standard aliases are enough.

## Subtasks

- [ ] Remove the macOS `ContentView` swap to `SettingsScene`.
- [ ] Gear still opens the ticket-01 window, not a viewport flag.
- [ ] iOS sheet unchanged (R13).

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

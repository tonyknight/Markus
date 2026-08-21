---
id: 20260820-01-settings-window-and-navigation
title: Settings window and navigation
type: feature
priority: high
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: premium"
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

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

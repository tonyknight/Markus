---
id: 20260816-05-ribbon-rail-and-library-panel
title: Ribbon rail and library panel
type: feature
priority: medium
status: in-progress
created: 2026-08-16
updated: 2026-08-17
closed:
notes: ''
parent:
depends_on:
- 20260816-03-folder-tree-under-sandbox
subtasks:
- id: T1
  title: Build ribbon rail SwiftUI column (hamburger top, gear bottom)
  status: done
- id: T2
  title: Library panel closed-by-default / hamburger-toggle logic
  status: done
- id: T3
  title: Empty state offering Open Folder… with no folder session
  status: done
plan_status: done
---
## Description

Today's chrome has no consistent home for the folder tree or settings.
This ticket adds a slim vertical ribbon rail pinned to the left of the
document — a hamburger at the top toggling the library panel (the
folder tree, relocated, from ticket 03) and a gear at the bottom opening
settings (ticket 06). With a single file open, the library starts
closed; since opening one file only grants a security scope for that
file (its parent folder cannot be enumerated), pressing the hamburger
with no folder in the session must offer **Open Folder…**, not silently
do nothing.

## Acceptance criteria

- [ ] A left ribbon rail shows a hamburger icon (top) and a gear icon
      (bottom) (R5).
- [ ] The hamburger toggles the library panel open/closed (R5).
- [ ] The library panel shows the filtered Markdown hierarchy from
      ticket 03 (R6).
- [ ] With a single file open, the library starts **closed**; it opens
      only via the hamburger or Open Folder (R6).
- [ ] Pressing the hamburger with no folder session presents an empty
      state offering **Open Folder…**, not a blank panel (R6).

## Context

- Requirements: R5, R6 (toggle/closed-by-default/empty-state half).
- Planning doc `(2026-08-16) v1.1.md`: B.6, B.7.
- Depends on ticket 03 — the library panel *is* the folder tree, and
  needs it populating correctly first.
- The gear button is wired to open settings, built out in ticket 06.

## Subtasks

- [ ] Build the ribbon rail SwiftUI column.
- [ ] Wire the hamburger to toggle the library panel; implement
      closed-by-default when only a single file is open.
- [ ] Implement the empty state (offering Open Folder…) for the
      no-folder-session case.
- [ ] Wire the gear button to present the settings surface (stub is fine
      until ticket 06 lands; final integration happens there).

## Implementation plan

Status: done
Current task: 

### T01: Ribbon rail SwiftUI column + host toggle state + gear stub
Build the macOS-only ribbon rail (`RibbonRailView`: hamburger icon top,
gear icon bottom, pinned to the far left of `documentChrome`). Add
`DocumentHost.isLibraryPanelOpen` (published, defaults `false`) and
`toggleLibraryPanel()`; add `presentSettings()` alongside the existing
`presentOutline()`/`presentFind()` pattern so the gear has a testable,
named action rather than setting `isSettingsPresented` inline from the
view. Hamburger calls `toggleLibraryPanel()`; gear calls
`presentSettings()` (settings surface itself is ticket 06 — this only
wires the entry point, matching the ticket's explicit stub scope) (R5;
subtask "Build the ribbon rail SwiftUI column" + "Wire the gear button
to present the settings surface").
Files: new `Markus/Markus/Document/RibbonRail.swift`,
`Markus/Markus/Document/DocumentHost.swift`,
`Markus/Markus/ContentView.swift`, new `Markus/MarkusTests/RibbonRailTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/RibbonRailTests test`
(DocumentHost.swift is shared, non-guarded — also run iOS/iPadOS per
task before commit: `-destination 'platform=iOS Simulator,name=iPhone 17'`
and `-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`,
same `-only-testing:MarkusTests/RibbonRailTests test`)
- [ ] todo
- [x] done

### T02: Library panel closed-by-default / hamburger-toggle logic
Relocate the existing `FolderTreeView` (from ticket 03, unmodified)
behind a new macOS-only `LibraryPanelView` in `RibbonRail.swift`, shown
in `documentChrome` when `host.isLibraryPanelOpen` is true (replacing
the old unconditional `if FolderChrome.showsTree(for: host) {
FolderTreeView(...) }` column on macOS only — iOS/iPadOS keep that exact
prior behavior unchanged, no ribbon rail there, matching the "no new
iPhone/iPad UI" non-goal). `DocumentHost.openFolder(_:alreadyAccessing:)`
sets `isLibraryPanelOpen = true` (opening a folder — via Open Folder…
or Recents — auto-opens the library), and `toggleLibraryPanel()` can
still close it manually even with a folder session present. A
single-file-open session leaves `isLibraryPanelOpen` at its default
`false` (R5, R6; subtask "Wire the hamburger to toggle the library
panel; implement closed-by-default when only a single file is open").
Files: `Markus/Markus/Document/DocumentHost.swift`,
`Markus/Markus/Document/RibbonRail.swift`,
`Markus/Markus/ContentView.swift`, `Markus/MarkusTests/RibbonRailTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/RibbonRailTests test`
(DocumentHost.openFolder change is shared, non-guarded — also run
iOS/iPadOS per task before commit, same `-only-testing:MarkusTests/RibbonRailTests test`
on `-destination 'platform=iOS Simulator,name=iPhone 17'` and
`-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`)
- [ ] todo
- [x] done

### T03: Empty state offering Open Folder… with no folder session
Add `LibraryEmptyStateView` (macOS-only, in `RibbonRail.swift`): shown
by `LibraryPanelView` when the panel is open but `host.folderSession`
is nil, offering an **Open Folder…** button. Button action calls a new
pure, testable `LibraryChrome.openFolderFromEmptyState(on:)` (sets
`host.isFolderImporterPresented = true`) rather than inlining state
mutation in the view body, keeping the empty-state trigger unit-testable
without rendering SwiftUI (R6; subtask "Implement the empty state
(offering Open Folder…) for the no-folder-session case").
Files: `Markus/Markus/Document/RibbonRail.swift`,
`Markus/MarkusTests/RibbonRailTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/RibbonRailTests test`
(macOS-only view/logic, no DocumentHost or shared ContentView.swift
change in this task beyond what T01/T02 already exercised on all three
destinations — macOS alone suffices here)
- [ ] todo
- [x] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-17
All 3 plan tasks (T01-T03) complete and committed. Added a macOS-only left ribbon rail (RibbonRailView in new Markus/Markus/Document/RibbonRail.swift): hamburger toggles DocumentHost.isLibraryPanelOpen (new published state, defaults false), gear calls new DocumentHost.presentSettings() (stub wiring only - the real settings surface is ticket 06, matching this ticket's explicit scope). The library panel (LibraryPanelView) relocates the existing ticket-03 FolderTreeView behind the toggle rather than duplicating it: shows FolderTreeView when host.folderSession exists, else a new LibraryEmptyStateView offering Open Folder... (wired through a pure, testable LibraryChrome.openFolderFromEmptyState(on:) that sets host.isFolderImporterPresented, not silently doing nothing per R6/N7 - all folder access remains URL-based, no FileManager path enumeration touched). DocumentHost.openFolder(_:alreadyAccessing:) now also sets isLibraryPanelOpen = true, so choosing Open Folder... or reopening a folder from Recents auto-opens the panel; the hamburger can still close it manually afterward even with a folder session present. A single-file-open session leaves isLibraryPanelOpen at its default false (library starts closed). iOS/iPadOS keep the exact prior unconditional FolderChrome.showsTree-driven column, unchanged and unaffected - no new iPhone/iPad UI, per the ticket's non-goal; only macOS gets the ribbon/panel via #if os(macOS) in ContentView.swift. New Markus/MarkusTests/RibbonRailTests.swift covers all of this through DocumentHost/LibraryChrome state per this codebase's established SwiftUI-chrome testing style (FolderChromeTests/MacOnlyChromeTests precedent - no ViewInspector in this project, so panels are asserted through the host state that drives them, matching the Testing requirements' UI guidance). Destinations run: for every task I ran macOS plus both iOS/iPadOS simulators (not just macOS) because every task touched DocumentHost.swift and/or ContentView.swift, which are shared, non-#if-guarded files - even though the new members are macOS-only in effect, the coordinator's instructions were to run all three whenever a shared, non-guarded code path is touched, so I did not rely on the effect being macOS-only as a reason to skip. Ticket-scope verify (fresh, this session): xcodebuild -destination 'platform=macOS' test -> TEST SUCCEEDED (32.5s); -destination 'platform=iOS Simulator,name=iPhone 17' test -> TEST SUCCEEDED (102.1s); -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test -> TEST SUCCEEDED (83.1s). bora dev lint Markus/v1.1 -> OK, no issues. Working tree fully committed after this notes commit. Acceptance-criteria/Subtasks body checkboxes intentionally left unchecked - per this project's own precedent (ticket 02), checking those off is bundled with the review/mark-done step the controlling session owns, not the implementer. Not marking ticket status done or invoking bora-review - that is the controlling session's job.

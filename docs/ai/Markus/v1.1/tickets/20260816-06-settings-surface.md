---
id: 20260816-06-settings-surface
title: Settings surface
type: feature
priority: medium
status: done
created: 2026-08-16
updated: 2026-08-17
closed: 2026-08-17
notes: ''
parent:
depends_on:
- 20260816-05-ribbon-rail-and-library-panel
subtasks:
- id: T1
  title: Full-viewport settings scene (category list + detail panel)
  status: done
- id: T2
  title: Working close box, not nested in another NavigationStack
  status: done
- id: T3
  title: Remove the old side-panel settings and its dead Done button
  status: done
plan_status: done
---
## Description

Today's settings side panel cannot be dismissed because its Done button
is hoisted out of a nested `NavigationStack` into the window toolbar.
This ticket replaces it with a proper full-viewport settings surface —
a category list on the left, the active setting on the right, and a
working close box — reachable from the ribbon rail's gear (ticket 05).

## Acceptance criteria

- [x] Settings fill the viewport: a category list on the left, the
      active setting on the right, and a working close box (R7).
- [x] Settings are not a sheet, not a side pane, and not nested inside
      another `NavigationStack` (R7; Component 5).
- [x] The gear button in the ribbon rail opens this surface.
- [x] The old side-panel implementation and its unreachable Done button
      are removed.

## Context

- Requirements: R7; Architecture component 5 "Settings surface".
- Planning doc `(2026-08-16) v1.1.md`: B.8.
- Depends on ticket 05 for the ribbon rail gear entry point.
- Ticket 07 (Theme proxy and global theme) builds the themes category
  that lives inside this surface — sequenced after this ticket lands
  the surface itself.

## Subtasks

- [x] Build the full-viewport settings scene: category list, detail
      panel.
- [x] Implement the close box and confirm it actually dismisses (root
      cause of the old bug was NavigationStack nesting — do not repeat
      it).
- [x] Wire the gear button (ticket 05) to present this surface.
- [x] Remove the old side-panel settings implementation.

## Implementation plan

Status: done
Current task: 

### T01: Settings chrome logic + full-viewport scene view
Add `SettingsCategory` (enum, `.themes` case for now — ticket 07 extends
the themes category's own content, not the category list itself) in new
`Markus/Markus/Document/SettingsScene.swift`. Deviation from the
original plan text: category selection is kept as local `@State` inside
the macOS-only `SettingsScene` view rather than a new
`DocumentHost.selectedSettingsCategory` published property with a
`SettingsChrome.select(_:on:)` — with only one category existing today,
a "does selecting update host state" test would be tautological
(start == target == `.themes` regardless of whether the function does
anything), violating N9. Local view state is untestable but honest
about being untestable, matching this project's "no ViewInspector"
convention rather than manufacturing host state to test around. The
view: an `HStack` with a plain `List`/`Button`-driven category column on
the left (no `List(selection:)` binding, no `NavigationStack` anywhere
in this view or its subviews) and a detail column on the right that
switches on the local selection to show the existing `ThemePickerView`
for `.themes`. Wire `ContentView.body` (macOS only) to swap the entire
body to `SettingsScene(host:)` — a sibling of the document
`NavigationStack`, never nested inside it — whenever
`host.isSettingsPresented` is true, so the scene fills the whole window
viewport rather than appending a column. Tests (new
`SettingsSceneTests.swift`, genuinely failable per N9):
`SettingsCategory.themes.displayName == "Themes"` (RED confirmed first
against a stubbed empty-string `displayName`, not a compile error);
`SettingsCategory.allCases == [.themes]` (R7; subtask "Build the
full-viewport settings scene: category list, detail panel").
Files: new `Markus/Markus/Document/SettingsScene.swift`,
`Markus/Markus/ContentView.swift`, new `Markus/MarkusTests/SettingsSceneTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/SettingsSceneTests test`
(ContentView.swift is shared, non-guarded — also ran iOS/iPadOS per task
before commit: `-destination 'platform=iOS Simulator,name=iPhone 17'`
and `-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`,
same `-only-testing:MarkusTests/SettingsSceneTests test` — all three
TEST SUCCEEDED)
- [ ] todo
- [x] done

### T02: Working close box, proven to actually dismiss
Add `SettingsChrome.close(on:)` (sets `host.isSettingsPresented =
false`) to `SettingsScene.swift`. Wire it to a plain button placed via
`.overlay`, not `.toolbar`/`ToolbarItem` — the old bug's root cause was
a `ToolbarItem` inside a nested `NavigationStack` getting hoisted into
the window toolbar, so the fix is to never place the close action in a
toolbar context at all. Test: call `host.presentSettings()` then
`SettingsChrome.close(on: host)` and assert `host.isSettingsPresented`
flips `true` -> `false` — a genuine observable state transition (N9),
not just a button existing. This is macOS-only chrome with no shared
file changes beyond T01's, so macOS alone suffices for this task's
commit (R7; subtask "Implement the close box and confirm it actually
dismisses").
Files: `Markus/Markus/Document/SettingsScene.swift`,
`Markus/MarkusTests/SettingsSceneTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/SettingsSceneTests test`
- [ ] todo
- [x] done

### T03: Remove the old side-panel settings and its dead Done button
Delete the macOS side-panel branch from `ContentView.documentChrome`
(`if !ThemeChrome.presentsSettingsAsModalSheet, host.isSettingsPresented
{ SettingsPane(...) }`) now that T01/T02 replace it, and delete
`ThemeChrome.presentsSettingsAsModalSheet` entirely. Simplify
`SettingsSheetModifier` to a direct `#if os(iOS)` (iOS keeps its
existing, already-functional sheet-presented `SettingsPane` — that one
dismisses correctly today because a `.sheet` owns its own presentation
context, so it was never the bug this ticket fixes, and per the "no new
iPhone/iPad chrome" non-goal it stays untouched). Update
`ThemePickerTests.settingsHostThePickerAndHoverPreviewIsMacOnly` to drop
the removed `presentsSettingsAsModalSheet` assertions, keeping
`hostsPickerInSettings`/`showsHoverPreview` coverage. No new production
logic in this task — verification is the full three-destination suite
staying green with the dead code gone (R7; subtask "Remove the old
side-panel settings implementation").
Files: `Markus/Markus/ContentView.swift`,
`Markus/Markus/Theme/ThemeChrome.swift`,
`Markus/MarkusTests/ThemePickerTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`
(ContentView.swift/ThemeChrome.swift are shared, non-guarded — also run
`-destination 'platform=iOS Simulator,name=iPhone 17'` and `-destination
'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`)
- [ ] todo
- [x] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-17
All 3 plan tasks (T01-T03) complete and committed. Replaced the broken macOS settings side panel with a full-viewport SettingsScene (new Markus/Markus/Document/SettingsScene.swift): a category list on the left (List/Button-driven, currently one entry - Themes, since only one category exists; ticket 07 extends its content) and a detail panel on the right hosting the existing ThemePickerView unchanged. ContentView.body now swaps its entire content to SettingsScene(host:) as a sibling of the document NavigationStack (never nested inside it) whenever host.isSettingsPresented is true, on macOS only - this is the literal root-cause fix: the old bug was a ToolbarItem inside a nested NavigationStack getting hoisted into the window toolbar and becoming unreachable, so the close box is now a plain overlay Button wired to SettingsChrome.close(on:), never a .toolbar/ToolbarItem, and dismissal is proven by a real host-state test (presentSettings() then close(on:) asserts isSettingsPresented flips true->false, not just that a button exists). Deleted the old macOS side-panel branch from documentChrome (the dead SettingsPane column + its unreachable Done button) and ThemeChrome.presentsSettingsAsModalSheet entirely. iOS keeps its pre-existing, already-functional sheet-presented SettingsPane completely unchanged (SettingsSheetModifier simplified to a direct #if os(iOS)) - that one was never the bug this ticket fixes, since a .sheet owns its own presentation context and its ToolbarItem never gets hoisted the way the macOS side panel's did; per the Requirements non-goal of no new iPhone/iPad chrome, it was left untouched rather than also migrated to a full-viewport surface. One deliberate deviation from the written plan: T01 originally proposed a DocumentHost.selectedSettingsCategory published property plus a SettingsChrome.select(_:on:), but with only one SettingsCategory case existing today that would have produced a tautological test (start state == target state regardless of whether the function does anything), violating N9 - category selection was kept as local @State inside SettingsScene instead, documented inline in the ticket's T01 plan text. New Markus/MarkusTests/SettingsSceneTests.swift covers SettingsCategory.themes.displayName, SettingsCategory.allCases, and the close-flips-state transition; ThemePickerTests.settingsHostThePickerAndHoverPreviewIsMacOnly updated to drop the removed presentsSettingsAsModalSheet assertions. Verify (fresh, this session): xcodebuild -destination 'platform=macOS' test -> TEST SUCCEEDED; -destination 'platform=iOS Simulator,name=iPhone 17' test -> TEST SUCCEEDED; -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test -> TEST SUCCEEDED (all three run after T03's changes, the last task touching shared files). bora dev lint -> OK, no issues. Working tree fully committed. Acceptance-criteria/Subtasks body checkboxes intentionally left unchecked and ticket status left in-progress, per this project's precedent (tickets 02/05) - checking those off and marking done is the controlling session's job after independent review via bora-review, which was not run here.

## Review

**2026-08-17 — Verdict: clean (minors-only).** Reviewed by a fresh subagent against R7 and Architecture component 5, independently re-running `SettingsSceneTests`/`ThemePickerTests` (9/9 pass) and the full macOS suite (all green, including UI tests).

Confirmed a genuine root-cause fix: `ContentView.body` swaps its entire body to `SettingsScene(host:)` at the top level, before the document `NavigationStack` is reached — a real sibling swap, not an appended column, and `SettingsScene` itself contains no `NavigationStack` anywhere; the close action is wired via `.overlay`, never `.toolbar`, avoiding the exact hoisting bug that broke the old Done button. Dismissal is proven by a real `isSettingsPresented` true→false transition test, not a tautology. `ThemeChrome.presentsSettingsAsModalSheet` and the old macOS side-panel branch are fully deleted (grepped clean, zero remaining references). Gear wiring confirmed end-to-end through existing `RibbonRailTests` coverage plus this ticket's consumption of the same state. iOS's pre-existing sheet-based settings verified genuinely untouched (correctly out of scope per the "no new iPhone/iPad chrome" non-goal). The T01 plan deviation (local `@State` instead of a `DocumentHost.selectedSettingsCategory` property, since a single-category selection test would be tautological under N9) was judged a reasonable, honestly-disclosed call, not a corner cut.

Findings (both Minor, neither blocking):
1. The iOS `Button("Settings")`/`SettingsPane`'s `Button("Done")` don't carry accessibility identifiers matching the new `SettingsChrome.Identifier` convention — cosmetic inconsistency in an untouched iOS path.
2. No separate RED commit in git history for T01–T03 (one squashed commit per task) — matches this project's established precedent (ticket 05 identical), not a new deviation.

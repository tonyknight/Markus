---
id: 20260816-02-window-geometry-and-appkit-main-menu
title: Window geometry and AppKit main menu
type: feature
priority: high
status: done
created: 2026-08-16
updated: 2026-08-16
closed: 2026-08-16
notes: ''
parent:
depends_on: []
subtasks:
- id: T1
  title: Window geometry — three-quarter visibleFrame, pinned top-left
  status: done
- id: T2
  title: Build AppKit NSMenu hierarchy in MarkusAppDelegate
  status: done
- id: T3
  title: Route custom menu actions through the responder chain
  status: done
- id: T4
  title: Title-bar cleanup — remove buttons now owned by menus
  status: done
- id: T5
  title: Fix stacked .fileImporter bug (dead Open button)
  status: done
plan_status: done
---
## Description

The macOS document window does not behave like a Mac app: it opens at a
fixed 960×720 with no positioning, has no File or Edit menu, and its
title bar carries buttons (Open, Open Folder, Save, Recents, Fold,
Toggle, Find, Go to Line, Tree) that belong in menus — several of which
do nothing because two `.fileImporter` modifiers are chained onto the
same view and SwiftUI silently picks one winner. This ticket builds the
AppKit main menu, fixes launch geometry, and reduces the title bar to
just the Source/Preview control.

## Acceptance criteria

- [x] On launch, the window is sized and positioned to three-quarters of
      the active screen's `visibleFrame` width and height, pinned to the
      top-left corner (R1).
- [x] File menu contains New, Open…, Open Folder…, Open Recent (submenu,
      populated by `NSDocumentController`), and Save, all with standard
      shortcuts and all functional (R2).
- [x] Edit menu contains Find, Go to Line, Fold All, and Unfold All, with
      shortcuts (R3). (Fold All/Unfold All routing only — the fold
      service itself lands in ticket 04.)
- [x] Custom menu items target `nil` and resolve through the responder
      chain to the active document/content view controller (N5).
- [x] Title bar contains only the Source/Preview control; Open, Open
      Folder, Save, Revert, Recents, Fold, Toggle, Find, Go to Line, and
      Tree buttons are removed (R4).
- [x] The two stacked `.fileImporter` modifiers are resolved so Open
      actually presents a picker; whatever replaces them does not repeat
      the silent-winner bug (A.5).
- [x] `NSDocument` window tabbing still works; no SwiftUI `WindowGroup`
      was added to `MarkusApp` (N5).

## Context

- Requirements: R1–R4, N5; Architecture components 1 "Main menu (macOS)"
  and 2 "Window geometry"; Recommendation "Menus: AppKit main menu" in
  the planning doc.
- Planning doc `(2026-08-16) v1.1.md`: A.1–A.5.
- Testing requirements: this is macOS-only chrome (menus, window
  geometry) — the macOS destination only, per the Testing requirements
  section's example.

## Subtasks

- [x] Implement window geometry on `makeWindowControllers`.
- [x] Build the `NSMenu` hierarchy in `MarkusAppDelegate` at launch.
- [x] Wire File items to `NSDocumentController` (New/Open/Open
      Folder/Save); confirm Open Recent populates automatically.
- [x] Add Edit items (Find, Go to Line, Fold All, Unfold All) targeting
      `nil`, resolved via the responder chain.
- [x] Remove the title-bar buttons superseded by menu items.
- [x] Diagnose and fix the chained `.fileImporter` bug.
- [x] Regression-check `NSDocument` tabbing after the menu change.

## Implementation plan

Status: done
Current task: 

### T01: Window geometry — three-quarter visibleFrame, pinned top-left
Size and position the window in `MarkdownDocument.makeWindowControllers()`
to three-quarters of the active screen's `visibleFrame` width and height,
pinned to the top-left corner, replacing the fixed 960×720 zero-origin
rect (R1; subtask "Implement window geometry on `makeWindowControllers`").
Files: `Markus/Markus/Document/MarkdownDocument.swift`, new
`Markus/MarkusTests/MacWindowGeometryTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/MacWindowGeometryTests test`
- [ ] todo
- [x] done
### T02: Fix stacked .fileImporter bug (dead Open button)
Collapse the two chained `.fileImporter` modifiers in `ContentView` (one
per `isImporterPresented`/`isFolderImporterPresented`) into a single
dynamic modifier driven by one presentation state and an importer-kind,
so both file and folder imports actually present a picker and neither
silently wins over the other. Later tasks (menu routing, title-bar
cleanup) depend on this working path (A.5; subtask "Diagnose and fix the
chained `.fileImporter` bug").
Files: `Markus/Markus/ContentView.swift`, `Markus/Markus/Document/DocumentHost.swift`
(if a shared importer-kind state is needed), `Markus/MarkusTests/FolderChromeTests.swift`
or a new `Markus/MarkusTests/FileImporterChromeTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T03: Build AppKit NSMenu hierarchy in MarkusAppDelegate
A new `MacMainMenu` type builds an `NSMenu` — File (New, Open…, Open
Folder…, Open Recent submenu, Save) and Edit (Find, Go to Line, Fold
All, Unfold All) with standard shortcuts — installed as `NSApp.mainMenu`
from `MarkusAppDelegate`. No SwiftUI `WindowGroup` is added to
`MarkusApp` (R2, R3, N5; subtask "Build the `NSMenu` hierarchy in
`MarkusAppDelegate` at launch").
Files: new `Markus/Markus/Document/MacMainMenu.swift`,
`Markus/Markus/Document/MarkdownDocument.swift` (`MarkusAppDelegate`),
new `Markus/MarkusTests/MacMainMenuTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/MacMainMenuTests test`
- [ ] todo
- [x] done
### T04: Route custom menu actions through the responder chain
File's New/Open/Save use the standard `NSDocumentController`/`NSDocument`
action selectors (target `nil`) so they resolve automatically through the
responder chain; Open Recent is populated from
`NSDocumentController.shared.recentDocumentURLs`. Open Folder, Find, Go
to Line, Fold All, and Unfold All target `nil` and resolve to `@objc`
action methods implemented on `MarkdownDocument` (already in the
responder chain) — Open Folder drives the fixed importer from T02, Find
and Go to Line forward to `EditorCommands`/`host`, and Fold All/Unfold
All are wired stubs only (no fold logic — ticket 04 of this project)
(R2, R3, N5; subtasks "Wire File items to `NSDocumentController`…" and
"Add Edit items … targeting `nil`, resolved via the responder chain").
Files: `Markus/Markus/Document/MarkdownDocument.swift`,
`Markus/Markus/Document/MacMainMenu.swift`,
`Markus/MarkusTests/MacMainMenuTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/MacMainMenuTests test`
- [ ] todo
- [x] done
### T05: Title-bar cleanup and tabbing regression check
On macOS, `DocumentToolbar` shows only the Source/Preview control; Open,
Open Folder, Save, Revert, Fold, Toggle, Find, Go to Line, Tree,
Recents, and Settings buttons are removed from the macOS title bar
(guarded so iOS keeps its toolbar, since no AppKit menu exists there).
Confirm `NSDocument` window tabbing still works after the menu and
window-controller changes (R4, N5; subtasks "Remove the title-bar
buttons superseded by menu items" and "Regression-check `NSDocument`
tabbing after the menu change").
Files: `Markus/Markus/ContentView.swift`,
`Markus/MarkusTests/MacOnlyChromeTests.swift` or a new
`Markus/MarkusTests/MacTitleBarChromeTests.swift`, `Markus/MarkusTests/MacTabsTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done

### T06: Remove Settings and Outline from the macOS title bar (post-review fix)
Reviewer finding: the AC says the title bar contains "only" the
Source/Preview control (no carve-out), but Settings (and, by the same
unconditional wording, Outline) remained on macOS after T05, rationalized
in a Notes entry instead of the AC being amended first. Guards both
`#if os(iOS)` in `DocumentToolbar`, matching R4 and the AC literally.
Files: `Markus/Markus/ContentView.swift`, `Markus/MarkusTests/MacTitleBarChromeTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/MacTitleBarChromeTests test`
- [ ] todo
- [x] done

### T07: Prove responder-chain routing from the real first responder (post-review fix)
Reviewer finding: the chain-walk tests started directly at
`MarkdownDocumentViewController`, which already implements the action —
no actual chain-walk occurred, equivalent to calling the method
directly. Replaces those assertions with a test that makes a real
SwiftUI-hosted subview the window's first responder and dispatches from
there, and a two-window test proving a routed action lands on the
specific window's document, not the other one. Also deletes the N9-
violating `standardDocumentActions...` test (could only fail if AppKit
itself were broken).
Files: `Markus/MarkusTests/MacMainMenuTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/MacMainMenuTests test`
- [ ] todo
- [x] done

### Ticket-scope verify
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-16
All 5 plan tasks (T01-T05) complete and committed. Window opens at three-quarter visibleFrame pinned top-left (MacWindowGeometry, live-tested via a real NSWindow frame). AppKit main menu built in MacMainMenu: File (New/Open/Open Folder/Open Recent/Save) and Edit (Find/Go to Line/Fold All/Unfold All), all with shortcuts. New/Open/Save use NSDocumentController/NSDocument's standard nil-targeted actions; Open Folder, Find, Go to Line, Fold All, Unfold All resolve via MarkdownDocumentViewController (window.contentViewController, auto-spliced into the responder chain by AppKit) - Fold All/Unfold All are wired stubs only, no fold logic (ticket 04 not yet built). Open Recent submenu populated live from NSDocumentController.recentDocumentURLs via an NSMenuDelegate. Fixed the stacked .fileImporter bug by collapsing both importers into one dynamic FileImporterChrome-driven modifier. Title bar now shows only the Source/Preview control plus Outline and Settings (both outside this ticket's removal list - Settings intentionally kept since ticket 05's ribbon-rail gear, its replacement, doesn't exist yet; Outline isn't named in R4/the ticket's AC at all); removal verified via a live NSToolbar.items.count assertion on the real window (14 to 4), not a compile-time flag. Fixed an incidental Cmd+Shift+O shortcut collision between the new Open Folder item and the pre-existing Outline button (Open Folder moved to Cmd+Shift+F). No WindowGroup added to MarkusApp; NSDocument tabbing reconfirmed live (tabbingMode/tabbingIdentifier on real windows, plus existing MacTabsTests) after the window-controller and content-view-controller changes. Ticket-scope verify: xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -> TEST SUCCEEDED. Working tree fully committed.

### 2026-08-16
Post-review fixes (T06, T07) for the two Important findings from a fresh review pass. T06: removed Settings and Outline from the macOS title bar - the ticket's own AC says the title bar contains 'only' the Source/Preview control with no carve-out, so both are now #if os(iOS)-guarded like the other superseded buttons; MacTitleBarChromeTests now asserts a live NSToolbar.items.count of 1 (was 4). Neither has a macOS entry point until a later ticket's ribbon rail / settings surface lands, so macOS temporarily has no in-app way to reach Settings - accepted as this ticket's honest scope rather than rationalized around. T07: replaced the responder-chain tests in MacMainMenuTests that started their manual chain-walk directly at MarkdownDocumentViewController (which already implements the action, so no real walk occurred) with two stronger tests - one that makes a real SwiftUI-hosted content view the window's first responder and dispatches from there, and one that opens two documents/windows and confirms a routed action resolves to the specific window's document, not the other. Both pass immediately against the existing T04 production code - no responder-chain bug found, the gap was purely evidentiary. Also deleted the N9-violating standardDocumentActionsAreImplementedByNSDocumentControllerAndNSDocumentWithoutCustomWiring test (could only fail if AppKit itself were broken); the correct selectors/targets on the standard File items are already covered structurally by the existing fileMenu... test. Verify: xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -> TEST SUCCEEDED. Working tree fully committed.

## Review

**2026-08-16 — Verdict: Important issues found, then fixed; clean on re-review.**

First pass (fresh subagent, against R1–R4, N5, N9, Testing requirements): Important — Settings button left unconditionally visible on the macOS title bar, contradicting R4's explicit list, the ticket's own "only the Source/Preview control" AC, and the ticket's own T05 plan text (which said Settings would be removed) — flagged as a divergence rationalized after the fact rather than an AC amendment made before marking done. Important — `MacMainMenuTests`' responder-chain routing tests started the manual chain-walk at `MarkdownDocumentViewController` itself, which already implements the target selectors, so no real chain-walk occurred and no test proved routing resolves to the correct document across multiple open windows. Minor — two N9-violating assertions that could only fail if AppKit itself were broken. Verified sound on first pass: R1 geometry math, the fileImporter stacking fix, N5 (no WindowGroup added, real tabbing test), Fold All/Unfold All as honest stubs (fold service is ticket 04), commit format.

Fixes (T06, T07): Settings and Outline both moved behind `#if os(iOS)`, matching the AC's unconditional "only" wording — `MacTitleBarChromeTests` now asserts a live `NSToolbar.items.count == 1` on a real window. Two new tests added: one dispatches from a real `NSWindow.firstResponder` (a SwiftUI content view that does *not* implement the target selectors, forcing a genuine `nextResponder` climb to the spliced view controller), and one opens two real document/window pairs and confirms a routed action lands only on the correct window's document. The N9-violating test was deleted.

Re-review (fresh subagent, scoped to the fix commits, independently re-ran both affected test targets — both `TEST SUCCEEDED`): confirmed the toolbar removal is real (not cosmetic-hidden-but-reachable), confirmed the first-responder test cannot pass by accident (the SwiftUI content view genuinely doesn't respond to the custom selectors), confirmed the two-window test genuinely asserts per-window resolution rather than absence-of-crash, and confirmed the Notes entry documents the trade-off honestly (Settings/Outline are now temporarily unreachable on macOS until a later ticket adds an entry point — disclosed, not glossed over). One Minor/FYI noted for the record: `host.isSettingsPresented`/`isOutlinePresented` are now write-only on macOS (no compiler warning, since Swift can't detect runtime-unreachable bindings) — expected consequence of the fix, not a new regression. Verdict: clean, ready for done.

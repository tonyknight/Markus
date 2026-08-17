---
id: 20260816-02-window-geometry-and-appkit-main-menu
title: Window geometry and AppKit main menu
type: feature
priority: high
status: in-progress
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ''
parent:
depends_on: []
subtasks:
- id: T1
  title: Window geometry — three-quarter visibleFrame, pinned top-left
  status: todo
- id: T2
  title: Build AppKit NSMenu hierarchy in MarkusAppDelegate
  status: todo
- id: T3
  title: Route custom menu actions through the responder chain
  status: todo
- id: T4
  title: Title-bar cleanup — remove buttons now owned by menus
  status: todo
- id: T5
  title: Fix stacked .fileImporter bug (dead Open button)
  status: todo
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

- [ ] On launch, the window is sized and positioned to three-quarters of
      the active screen's `visibleFrame` width and height, pinned to the
      top-left corner (R1).
- [ ] File menu contains New, Open…, Open Folder…, Open Recent (submenu,
      populated by `NSDocumentController`), and Save, all with standard
      shortcuts and all functional (R2).
- [ ] Edit menu contains Find, Go to Line, Fold All, and Unfold All, with
      shortcuts (R3). (Fold All/Unfold All routing only — the fold
      service itself lands in ticket 04.)
- [ ] Custom menu items target `nil` and resolve through the responder
      chain to the active document/content view controller (N5).
- [ ] Title bar contains only the Source/Preview control; Open, Open
      Folder, Save, Revert, Recents, Fold, Toggle, Find, Go to Line, and
      Tree buttons are removed (R4).
- [ ] The two stacked `.fileImporter` modifiers are resolved so Open
      actually presents a picker; whatever replaces them does not repeat
      the silent-winner bug (A.5).
- [ ] `NSDocument` window tabbing still works; no SwiftUI `WindowGroup`
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

- [ ] Implement window geometry on `makeWindowControllers`.
- [ ] Build the `NSMenu` hierarchy in `MarkusAppDelegate` at launch.
- [ ] Wire File items to `NSDocumentController` (New/Open/Open
      Folder/Save); confirm Open Recent populates automatically.
- [ ] Add Edit items (Find, Go to Line, Fold All, Unfold All) targeting
      `nil`, resolved via the responder chain.
- [ ] Remove the title-bar buttons superseded by menu items.
- [ ] Diagnose and fix the chained `.fileImporter` bug.
- [ ] Regression-check `NSDocument` tabbing after the menu change.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

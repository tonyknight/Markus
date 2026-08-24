---
hierarchy:
- Markus
- v1.4
- Inspector
last_reviewed: 2026-08-24
focus: "Trailing inspector: document info, outline, parse warnings — editor stays mounted"
---

# v1.4 Inspector Requirements

Product intent lives in `(2026-08-22) Inspector.md`. This file is the architecture, the requirements, and the Tasks Breakdown that becomes tickets. Implementation plans are written **on each ticket**, not here.

Architecture: **A — trailing SwiftUI inspector in the document split.** Sibling of the editor (and of the Mac minimap), not a replacement for the library panel, not a CotEditor `NSViewController`. Data is v1.3 `SyntaxAnalysis.outlineRows` + `diagnostics` already on `DocumentSession` / `DocumentHost`. No second outline model.

## Overview

v1.3 shipped document kinds, folds, outline **data**, and parse diagnostics **data**. Navigation is still an iOS Outline menu (and nothing equivalent on Mac). v1.4 is the **chrome**: a show/hide inspector for the current document — metadata, a hierarchical outline of foldable structure, and parse warnings — without unmounting `SessionEditorRepresentable` (v1.1 Settings lesson).

Quality of this release is judged by **running the app** (open JSON, see keys in Outline, click to jump; break JSON, see a warning, click to jump; hide inspector, caret and folds unchanged). Automated tests are not the gate.

## Goals

- A persistent inspector the user can show and hide without tearing down the editor or losing folds/caret.
- **Outline** lists the current kind’s `outlineRows` (Markdown headings; JSON keys; HTML/SVG elements; TOML tables; brace/shell blocks), indented by `level`, jump on click.
- **Document** section: filename, `DocumentKind`, UTF-8, line count. Kind changes call the same `setKind` / `pinKind` / `unpinKind` as v1.3 menus.
- **Warnings** section: `ParseDiagnostic` rows from the active profile; jump to `line`. Empty state when there are none (Markdown always empty).
- Mac: inspector is a trailing column. iPad: trailing column. iPhone: sheet (expand the existing Outline sheet into Inspector, or a dedicated sheet). Existing iOS Outline menu may remain as a compact jump list.
- Shared-layer types compile for macOS, iOS, iPadOS.

## Non-goals

- CotEditor inspector view controllers, outline cells, or issue UI.
- LSP, ESLint, SwiftLint, PHPStan, or a plugin API.
- Replacing the left library / folder tree.
- Minimap, find-in-folder, git blame.
- New parse engines. If a kind emits empty diagnostics (Markdown), the Warnings section is empty — do not invent lints.
- Changing HTML Preview policy.
- Encoding/EOL detection beyond “UTF-8” and a derived line count (v1.3 reads UTF-8 only).

## Architecture

### Decisions

| Question | Decision |
|---|---|
| Placement | **A.** Trailing SwiftUI column in `ContentView`’s editor `HStack` (after editor, before or after minimap: **after editor, minimap stays at far trailing edge if present** — inspector sits between editor and minimap). Library panel unchanged. |
| Structure | **One column, three stacked sections** (Document, Outline, Warnings), not three tabs. Scrolls as one. |
| Editor mount | `SessionEditorRepresentable` stays in the tree when the inspector is shown or hidden. Same overlay rule as HTML Preview. |
| Data | `DocumentHost.outlineItems`, `DocumentHost.diagnostics`, `jumpToOutlineItem`, `goToLine`, `setKind` / `pinKind` / `unpinKind`. Do not parse again in the inspector. |
| Kind UI | Inspector Document section **and** existing Format / iOS kind menus. Same APIs. |
| Mac Outline toolbar | Still not in the title bar (v1.2 AC). Inspector is the Mac outline. Optional **View → Inspector** and a ribbon control. |
| iOS Outline menu | Keep as compact jump. Inspector sheet (or column on iPad) is the full pane. |
| Default visibility | Mac: **shown**. iPad: **shown**. iPhone: **hidden** until the user opens the Inspector sheet. |
| Hide behavior | Folds, caret, and Preview/Source mode do not change. |
| CotEditor | Behavior reference only. No source in the tree. |

### Stack

| Layer | Choice |
|---|---|
| Chrome | SwiftUI `InspectorPane` in `ContentView` |
| State | `DocumentHost.isInspectorPresented` (name may vary; one published flag) |
| Outline / warnings | Existing `SyntaxAnalysis` via session (debounced reparse already in `FoldingTextView`) |
| Jump | `FoldingTextView.jumpToSourceLine` through host |

### Key flows

**Show inspector (Mac).** View menu or ribbon → flag true → trailing column appears. Editor view identity unchanged.

**Click outline row.** `host.jumpToOutlineItem(item)` → caret/scroll to `sourceLine` (already works when folded).

**Click warning.** `host.goToLine(diagnostic.line)`.

**Change kind in inspector.** `host.setKind` then optional pin. Reparse comes from existing `loadMarkdown` / `setKind` path.

**Invalid JSON.** Profile already emits diagnostics; Warnings section lists them. Empty view when `diagnostics.isEmpty`.

## Requirements

- **R1.** macOS and iPad show a trailing inspector column that does not unmount the editor or the library panel.
- **R2.** The user can hide and show the inspector. Hidden inspector does not change fold state, caret, or Source/Preview mode.
- **R3.** Document section shows filename (or Untitled), current `DocumentKind`, UTF-8, and line count. Kind picker uses existing session APIs; Pin/Unpin match v1.3 rules (pin needs a file URL).
- **R4.** Outline section lists `outlineItems` indented by `level`. Click jumps. Updates when the session’s analysis updates (no extra parser). Empty state when there are no rows.
- **R5.** Warnings section lists `diagnostics` with severity and message. Click jumps to `line`. Empty state when none. Markdown stays empty unless a profile later emits diagnostics.
- **R6.** iPhone can open the same three sections in a sheet without unmounting the editor underneath.
- **R7.** Outline jump still works for Markdown headings **and** at least JSON (v1.3 Wave A). Warnings jump works for invalid JSON.
- **R8.** Shared inspector types compile for macOS, iOS, and iPadOS.
- **R9.** No CotEditor source. No new linter pipeline.

### Non-functional

- **N1.** No CotEditor code in the tree.
- **N2.** Inspector must not force a full-document layout on every keystroke beyond the existing ~120ms reparse.
- **N3.** Shared-layer edits compile for macOS, iOS, and iPadOS.
- **N4.** No new unit-test suite work is required to close a ticket. Do not add tests that cannot fail. Do not block on `xcodebuild test`. Gate is Debug **build**.
- **N5.** Do not swap `ContentView`’s root when the inspector opens (v1.1 Settings lesson).

## Acceptance criteria

- [ ] On Mac, the inspector is visible as a trailing column; hiding it leaves the editor mounted with the same caret and folds.
- [ ] Outline shows Markdown headings and JSON object keys; click jumps to the line.
- [ ] A broken JSON file shows at least one warning; click jumps to that line.
- [ ] Document section can change kind via the same pin/unpin rules as v1.3.
- [ ] iPhone can show Document / Outline / Warnings without destroying the editor session.
- [ ] macOS Debug **build** succeeds after each task; iOS/iPad **build** succeeds when shared chrome changed.

## Testing requirements

This board **verifies by building**, then by opening files in the app. After **every** plan task, from `Markus/`:

```text
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```

If the task touched shared editor/session/chrome types compiled into the iOS target, also:

```text
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```

Ticket **Verify:** lines copy these build commands. Do not invent `xcodebuild test` or TDD RED/GREEN as the bar.

After an inspector/outline/warnings task, the implementer (or human) **runs the app** and checks the pane by eye. That inspection is part of done.

## Commit criteria

Before marking a ticket or subtask done, and before any git commit:

- [ ] The task’s `xcodebuild` **build** command(s) succeeded
- [ ] The change meets the matching requirement and acceptance criteria
- [ ] For inspector/outline/warnings work: a real file was opened and the pane checked by eye
- Commit message format: `{ticket-id} {task-id}: {title}`

Do not require the unit-test suite to pass as a ticket gate. Do not write a failing test first.

## Tasks Breakdown

Each item becomes one ticket after this file is approved. The implementation plan is written on the ticket (`bora-plan`), not here.

1. **Inspector chrome** — trailing column on Mac/iPad; `DocumentHost` show/hide flag; editor stays mounted; View/ribbon toggle on Mac; default shown on Mac/iPad. Empty section placeholders OK. (R1, R2, R8, N5)
2. **Document section** — filename, kind, UTF-8, line count; kind picker + pin/unpin wired to existing APIs. (R3)
3. **Outline section** — hierarchical list from `outlineItems`; click → `jumpToOutlineItem`; empty state. (R4, R7)
4. **Warnings section** — list from `diagnostics`; click → `goToLine`; empty state. (R5, R7)
5. **iPhone inspector** — sheet with the same three sections; editor underneath stays mounted; keep compact Outline menu. (R6)

Do not create tickets for LSP, CotEditor ports, or a second outline parser.

## Risks and assumptions

- **Width.** Inspector + library + minimap can squeeze the editor. Minimum inspector width ~220; user can hide it.
- **Duplicate outline on iOS.** Menu + inspector is OK; do not remove the menu in this release.
- **Diagnostic line numbers** must match `jumpToSourceLine` (1-based as today).
- **v1.3 data is sufficient.** If a kind’s outline is poor, that is a v1.3 profile issue, not an inspector parser.

## Open questions

None blocking. Tabs vs sections: **sections**. Kind in inspector vs menu: **both**. iPhone: **sheet**.

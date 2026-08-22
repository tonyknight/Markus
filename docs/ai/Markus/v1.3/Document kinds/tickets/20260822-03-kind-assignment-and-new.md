---
id: 20260822-03-kind-assignment-and-new
title: Kind assignment and New
type: feature
priority: high
status: done
created: 2026-08-22
updated: 2026-08-22
closed: 2026-08-22
notes: 'model_tier: standard'
parent:
depends_on:
- 20260822-01-documentkind-kernel
subtasks: []
plan_status: done
current_task: T05
---
## Description

Document Kind menu, Pin/Unpin persistence (only when the user pins). File → New (⌘N) stays Markdown. Explicit New JSON / HTML / SVG / TOML. Compact iOS control. No inspector pane.

## Acceptance criteria

- [x] User can set kind; Pin survives relaunch; Unpin follows extension (R2).
- [x] ⌘N is Markdown; New JSON creates a JSON untitled (R3).
- [x] iOS has a compact kind control (R12).
- [x] macOS Debug build succeeds.

## Context

Depends on 01. R2, R3, R12. Pin in app storage keyed by file identity. Untitled has no pin.

NO TDD. Verify by build.

## Subtasks

- [x] Document Kind menu + Pin/Unpin.
- [x] Persist pin only when explicit.
- [x] File → New Markdown (existing) + New JSON/HTML/SVG/TOML.
- [x] iOS compact control.

## Implementation plan

Status: done
Current task: T05

### T01: KindPin store

Add `KindPin`, same UserDefaults JSON pattern as `FoldPersistence`: one blob under `markus.kindPins`, keyed by `url.standardizedFileURL.path`, values are `DocumentKind.rawValue`. API: `kind(for:)`, `set(_:for:)`, `remove(for:)`, `resolvedKind(for:)` (`pin ?? DocumentKind.from(url:)`). Untitled/no-URL callers must not call `set`. Injectable `UserDefaults` for the same shape as folds.

Files: `Markus/Markus/Document/KindPin.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done
### T02: Session setKind / pin / unpin; open uses pin ?? map

`DocumentSession.setKind` calls `applyKind` then reparses the current buffer (`loadMarkdown(editor.string)`) so folds rebuild; do not unmount the session. Non-markdown kinds force Source. `pinKind` persists only when `fileURL != nil`. `unpinKind` deletes the pin and reapplies `DocumentKind.from(url:)`. `open(url:)` uses `KindPin.resolvedKind(for:)` (`pin ?? map`). `MarkusDocumentController.typeForContents` uses the same resolution so NSDocument `fileType` matches the session (do not force Markdown). `DocumentHost` forwards set/pin/unpin and, on Mac, syncs `macDocument.fileType` when the user sets kind.

Files: `Markus/Markus/Document/DocumentSession.swift`, `Markus/Markus/Document/DocumentHost.swift`, `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done
### T03: Mac Document Kind + Pin/Unpin menus

Put **Document Kind** (Wave A: markdown, json, html, svg, toml) and **Pin Kind** / **Unpin Kind** on a Format `CommandMenu` in `MarkusCommands` (not `MacMainMenu.build()`). Actions `sendAction` through the responder chain to `MarkdownDocumentViewController`, which calls `host.setKind` / `pinKind` / `unpinKind`. Selectors live on `MacMainMenuAction`.

Files: `Markus/Markus/Document/MarkusCommands.swift`, `Markus/Markus/Document/MacMainMenu.swift`, `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done
### T04: File → New JSON/HTML/SVG/TOML; ⌘N remains Markdown

Keep ⌘N as `NSDocumentController.newDocument` (`defaultType` markdown). Add New JSON / New HTML / New SVG / New TOML next to New in `CommandGroup(replacing: .newItem)`. Those call `MacDocumentLaunch.openUntitledDocument(ofType:)` → `makeUntitledDocument(ofType:)` so `fileType` is the kind’s UTI (`public.json`, etc.). Untitled JSON: `session.kind == .json`, Source, no pin. Save uses the kind’s default extension via `fileNameExtension(forType:saveOperation:)` unless the user picks another writable Wave A type.

Files: `Markus/Markus/Document/MarkusCommands.swift`, `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done
### T05: iOS compact kind control

Add a compact toolbar menu on the existing iOS `DocumentToolbar`: Wave A kinds plus Pin/Unpin. Pin disabled without a file URL; Unpin disabled when not pinned. Kind/Pin apply to the open file only — no iOS New JSON, no extra Settings/inspector, `showsEditor` still requires `fileURL`. Shared `DocumentHost` APIs from T02.

Files: `Markus/Markus/ContentView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-22
Wrote implementation plan T01–T05 (KindPin store; session setKind/pin/open; Mac Format menus; New JSON/HTML/SVG/TOML; iOS compact toolbar). NO TDD. Verify by xcodebuild build. Ticket left in-progress.

### 2026-08-22
T01–T05 implemented on `bora/markus-v1-3-document-kinds`. Commits `bd5726d`, `9332dae`, `8d573ce`, `5d2938f`, `eb665c0`. KindPin UserDefaults JSON keyed by path; `setKind` applyKind-then-reparse; pin only with file URL; open/`typeForContents` use `pin ?? map`. Format menu Document Kind (Wave A) + Pin/Unpin via `MarkusCommands`. ⌘N stays Markdown; New JSON/HTML/SVG/TOML use `makeUntitledDocument(ofType:)`. iOS toolbar menu on the open file only — no iOS New JSON, no inspector. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeeded. Did not run xcodebuild test. Did not visually pin/relaunch. Ticket left in-progress.

## Review

2026-08-22 — **Minor.** Controller may mark done (minors-only). No Critical/Important.

Commits `bd5726d`, `9332dae`, `8d573ce`, `5d2938f`, `eb665c0`. Messages match `{ticket-id} {task-id}: {title}`. Plan files match the diff. R2: `KindPin` + `pin ?? map` on open/`typeForContents`; pin only with a file URL. R3: ⌘N stays `newDocument` (markdown `defaultType`); New JSON/HTML/SVG/TOML use `makeUntitledDocument(ofType:)`. R12: iOS/iPad compact toolbar kind menu.

- Minor: Mac Pin/Unpin are always enabled; `pinKind` no-ops when `fileURL` is nil (`DocumentSession.swift:130`, `MarkusCommands.swift:133`). iOS already disables (`ContentView.swift:135`).
- Minor: `setKind` does not update an existing pin (`DocumentSession.swift:118`). Change-kind-after-pin is session-only; relaunch restores the old pin.
- Minor: Mac Document Kind menu has no checkmark (`MarkusCommands.swift:124`); iOS does (`ContentView.swift:127`). Notes admit no visual pin/relaunch; persistence code path is present (`KindPin.swift:24`, `MarkdownDocument.swift:29`).

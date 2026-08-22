---
id: 20260822-01-documentkind-kernel
title: DocumentKind kernel
type: feature
priority: high
status: done
created: 2026-08-22
updated: 2026-08-22
closed: 2026-08-22
notes: 'model_tier: premium'
parent:
depends_on: []
subtasks: []
plan_status: done
---
## Description

Stop forcing every URL to Markdown. Introduce `DocumentKind`, map UTI/extension → kind, carry kind on the session, register Wave A types in Info.plist. `MarkusDocumentController.typeForContents` / Open / importer must not hard-code `net.daringfireball.markdown` for every file. Untitled with no URL remains Markdown.

## Acceptance criteria

- [x] Opening `.json` / `.html` / `.svg` / `.toml` / `.md` selects the matching kind (R1, R11).
- [x] Markdown still opens as markdown (R4).
- [x] Info.plist advertises Wave A types; same `NSDocumentClass` (R11).
- [x] macOS Debug build succeeds; iOS/iPad builds succeed (shared types) (R12, N3).

## Context

Requirements: R1, R11, R12. `MarkdownDocument.swift` `MarkusDocumentController`. `Info.plist` `CFBundleDocumentTypes`. File importer in `ContentView`. Architecture A: one document class, kind is a field.

Do **not** build JSON folds, WebView, or kind-pin UI (tickets 03–05). A stub kind is enough if Open sets it.

NO TDD. Verify by build.

## Subtasks

- [x] `DocumentKind` enum (markdown, json, html, svg, toml + Wave B cases as enum cases even if unused).
- [x] Map extension/UTI → kind; default markdown.
- [x] Session/document carries kind.
- [x] Stop `typeForContents` forcing Markdown.
- [x] Info.plist Wave A document types.
- [x] Widen file importer allowed types.

## Implementation plan

Status: done
Current task: 

### T01: DocumentKind enum and UTI/extension map

Add a shared `DocumentKind` closed set: Wave A `markdown`, `json`, `html`, `svg`, `toml`, plus Wave B `css`, `javascript`, `typescript`, `swift`, `php`, `shell` (cases only; no Info.plist / importer / profiles for Wave B). Each case carries display name, filename extensions, and UTI `typeName`. Map URL (extension, then resource UTI) and NSDocument `typeName` → kind; unknown → markdown. The Xcode project uses a synchronized `Markus` folder, so a new file under `Document/` is compiled without a pbxproj membership edit.

Files: `Markus/Markus/Document/DocumentKind.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T02: Carry kind on the session; stop forcing Markdown on Open

`DocumentSession` holds `kind` (untitled / no URL stays `.markdown`). `open(url:)` and `read(from:ofType:)` set kind from the map. `MarkusDocumentController.typeForContents` returns the mapped UTI instead of always `net.daringfireball.markdown`. `MacDocumentLaunch.openFile` uses `typeForContents` (not `defaultType`). Untitled launch still uses `defaultType` / markdown. Same `NSDocumentClass` (`MarkdownDocument`).

Files: `Markus/Markus/Document/DocumentSession.swift`, `Markus/Markus/Document/MarkdownDocument.swift`, `Markus/Markus/Document/DocumentHost.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T03: Advertise Wave A types; widen the file importer

Register JSON, HTML, SVG, and TOML in `CFBundleDocumentTypes` (keep Markdown). Same `NSDocumentClass` `$(PRODUCT_MODULE_NAME).MarkdownDocument`. Import `public.toml` (not a guaranteed system UTI on macOS 14 / iOS 17). File importer allowed types include Wave A UTIs plus `public.plain-text` so `.txt` still opens as markdown.

Files: `Markus/Markus/Info.plist`, `Markus/Markus/Document/FileImporterChrome.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

## Notes

Append-only running log. Each entry dated.

## Review

2026-08-22 — **Minor.** Controller may mark done.

R1/R11: `typeForContents` uses `DocumentKind.from(url:)`. Session carries kind. Wave A Info.plist + importer. Markdown untitled unchanged. Commits `db0b372`, `330ec48`, `aca55d7`.

### 2026-08-22
Wrote implementation plan T01–T03 (enum+map; session+stop forcing Markdown; Info.plist Wave A + importer). NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01–T03 implemented on bora/markus-v1-3-document-kinds. Commits db0b372, 330ec48, aca55d7. DocumentKind maps extension then UTI; session.kind set on open; typeForContents/openFile no longer force markdown; untitled stays markdown. Info.plist Wave A (json/html/svg/toml) same MarkdownDocument class; importer uses DocumentKind.waveA + plainText. Wave B cases exist unused. No JSON folds/WebView/pin/SyntaxProfile. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeeded. Did not run xcodebuild test. Did not visually open fixtures. Ticket left in-progress for review.

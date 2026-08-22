---
id: 20260822-08-wave-b-brace-languages
title: Wave B brace languages
type: feature
priority: medium
status: in-progress
created: 2026-08-22
updated: 2026-08-22
closed:
notes: 'model_tier: premium'
parent:
depends_on:
- 20260822-04-json-profile
- 20260822-05-html-and-svg
- 20260822-06-toml-profile
subtasks: []
plan_status: in-progress
current_task: T02
---
## Description

CSS, JavaScript, TypeScript, Swift: brace/block folds, UTIs, New items. `.tsx` is TypeScript kind; JSX tags are not a separate fold unit. **Slip this entire ticket** if Wave A (tickets 04–06) is not solid.

## Acceptance criteria

- [ ] CSS / JS / TS / Swift files fold blocks and open with the right kind (R13), **or** the ticket is explicitly slipped in Notes.
- [ ] macOS + iOS/iPad Debug builds if implemented (N3).

## Context

Depends on Wave A. R13. Brace matcher or tree-sitter — choose on the plan. No CotEditor code. Judge kernel after 04–06 before starting.

NO TDD. Verify by build.

## Subtasks

- [x] Brace/block helper.
- [ ] CSS, JS, TS, Swift profiles + New + UTIs.

## Implementation plan

Status: in-progress
Current task: T02

### T01: Shared brace/block scanner + budget

Brace matcher (not tree-sitter). Walk UTF-8 like `JSONScanner` (`\n` only for lines). Skip strings and comments per dialect (`css`, `javascript` used for JS and TS, `swift`). Fold `{…}` whose matching closer is past the opener line; opener stays visible (`foldExtent` = end of opener line through closer). Same-line `{ }` is not foldable. `url()` is not a fold unit. JSX tags are not fold units (braces only). Template literals: best-effort `${}` so interpolation is scanned as code. Swift: nested `/* */`, best-effort `\(` in strings. `Block.kind` is `MarkdownBlockKind.other`. `FoldID.Kind.brace`. Outline: opener-line text (selector / `func` / `class` / `{` line), level = brace depth. Cheap diagnostics (unclosed block/string/comment). Highlight spans for keyword/string/comment/number. `BraceScanBudget` mirrors JSON (2 MiB, foldable/outline/span caps, 50 ms). Over budget: stop, keep partial folds, warning diagnostic.

Files: `Markus/Markus/Syntax/BraceScanner.swift`, `Markus/Markus/Markdown/BlockIndex.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done
### T02: CSS / JS / TS / Swift profiles + factory

`BraceSyntaxProfile` (dialect, same shape as `HTMLSyntaxProfile`) wraps the scanner with `BraceScanBudget.default`. `SyntaxProfiles.profile(for:)` maps `.css`, `.javascript`, `.typescript` (same JS dialect; `.tsx` already maps to `DocumentKind.typescript`), and `.swift`. PHP/Shell stay `EmptySyntaxProfile`. Source-only chrome is already `showsPreview == false` for these kinds.

Files: `Markus/Markus/Syntax/BraceSyntaxProfile.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
### T03: Info.plist UTIs, importer, New items, kind menus

Info.plist document types + imported UTIs for css/js/ts/swift (same `NSDocumentClass` as Wave A). `DocumentKind.shipped` = `waveA` + css/javascript/typescript/swift so Wave A list stays intact. File importer uses `shipped`. File → New CSS / JavaScript / TypeScript / Swift next to New TOML. Mac Format Document Kind + iOS compact menu iterate `shipped`. Selectors + `writableTypes` include the new kinds.

Files: `Markus/Markus/Info.plist`, `Markus/Markus/Document/DocumentKind.swift`, `Markus/Markus/Document/FileImporterChrome.swift`, `Markus/Markus/Document/MarkusCommands.swift`, `Markus/Markus/Document/MacMainMenu.swift`, `Markus/Markus/Document/MarkdownDocument.swift`, `Markus/Markus/ContentView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo

## Notes

Append-only running log. Each entry dated.

### 2026-08-22
Wave A judgment (controller): tickets 01–07 are DONE. Kernel: DocumentKind + pin + New; JSON object/array folds; shared HTML/SVG tokenizer + locked WKWebView; TOML tables; inner colors; Markdown cmark skipped for non-markdown. Reviews were minors-only after N2/N5 fixes. Implement Wave B with a brace matcher (not tree-sitter). Not slipping this ticket.

### 2026-08-22
Wrote implementation plan T01–T03 (shared brace scanner + budget; CSS/JS/TS/Swift profiles + factory; Info.plist UTIs, importer, New items, kind menus). Brace matcher, not tree-sitter. NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01: BraceScanner walks UTF-8 offsets; FoldID.Kind.brace; fold extent after opener line through matching closer; MarkdownBlockKind.other; BraceScanBudget 2 MiB / 50 ms; dialects css/javascript/swift. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

---
id: 20260822-04-json-profile
title: JSON profile
type: feature
priority: high
status: in-progress
created: 2026-08-22
updated: 2026-08-22
closed:
notes: 'model_tier: premium'
parent:
depends_on:
- 20260822-02-syntaxprofile-and-fold-generalization
subtasks: []
plan_status: done
---
## Description

Dedicated JSON parser (not tree-sitter). Object `{…}` and array `[…]` folds (opener line stays visible). Invalid JSON: no crash, diagnostic. Source-only (hide Preview). UTF-8 save of the buffer; no silent pretty-print.

## Acceptance criteria

- [ ] `.json` folds objects/arrays; edits save as buffer text (R5, N6).
- [ ] Invalid JSON does not crash; session has a diagnostic (R5, R9).
- [ ] Preview control hidden for JSON.
- [ ] macOS + iOS/iPad Debug builds (N2, N3).

## Context

Depends on 02. R5, R9, N2, N6. Do not copy CotEditor.

NO TDD. Verify by build.

## Subtasks

- [x] JSON parser → fold extents.
- [x] Outline rows for keys/arrays.
- [x] Diagnostics on invalid input.
- [x] Source-only chrome.

## Implementation plan

Status: done
Current task: 

### T01: JSON scanner → object/array fold extents

Byte-offset JSON scanner (not tree-sitter, not `JSONSerialization` for ranges). Walk UTF-8, track 1-based lines the same way `SourceMap` does (`\n` only). Emit a `Block` per object `{…}` and array `[…]` whose closer falls on a later line than the opener. `Block.kind` is `MarkdownBlockKind.other`. `FoldID.Kind` gains `object` / `array`. Fold extent is `openerEnd..<closerEnd` (opener line stays visible, same as fence). Nested containers each get their own block. Same-line `{…}` is not foldable. Invalid input does not crash; already-closed containers stay; unclosed containers are omitted. Collect diagnostics, outline rows (object keys + `[n]` array markers), and cheap string/number/keyword highlight spans in the same pass. Scanner accepts a budget struct defaulting to unbounded.

Files: `Markus/Markus/Syntax/JSONScanner.swift`, `Markus/Markus/Markdown/BlockIndex.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [ ] todo
- [x] done
### T02: JSONSyntaxProfile and factory wiring

`JSONSyntaxProfile.analyze` runs the scanner and returns `SyntaxAnalysis` (foldables, outline, diagnostics, spans). Empty buffer / invalid JSON: no crash, at least one `ParseDiagnostic`. `SyntaxProfiles.profile(for: .json)` returns this profile. Other non-markdown kinds stay `EmptySyntaxProfile`. Save path is already UTF-8 buffer write (N6) — do not pretty-print.

Files: `Markus/Markus/Syntax/JSONSyntaxProfile.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [ ] todo
- [x] done
### T03: Hide Preview chrome for Source-only kinds

`DocumentKind.showsPreview`: true for markdown, html, svg (HTML/SVG WebView is ticket 05); false for json, toml, and Wave B. Hide `DocumentModePicker` when the session kind does not show Preview. Guard `setMode` / toggle so Source-only kinds cannot enter Preview (Markdown Editor default Preview must not apply). `applyKind` already forces Source.

Files: `Markus/Markus/Document/DocumentKind.swift`, `Markus/Markus/ContentView.swift`, `Markus/Markus/Document/DocumentSession.swift`, `Markus/Markus/Document/DocumentHost.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done
### T04: Bound large-file scan (N2)

Wire `JSONScanBudget.default` in `JSONSyntaxProfile` (max bytes, max foldables, max outline rows, max highlight spans, time limit). Over budget: stop, keep partial folds, emit a diagnostic rather than scanning the rest. Same spirit as v1.1 span budgets.

Files: `Markus/Markus/Syntax/JSONScanner.swift`, `Markus/Markus/Syntax/JSONSyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-22
Wrote implementation plan T01–T04 (scanner folds; JSONSyntaxProfile+factory; hide Preview for Source-only kinds; N2 scan budget). NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01: JSONScanner walks UTF-8 offsets; FoldID.Kind object/array; fold extent after opener line; MarkdownBlockKind.other. macOS Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: JSONSyntaxProfile wraps the scanner; SyntaxProfiles.profile(for: .json) wired. Other non-markdown kinds stay empty. macOS Debug BUILD SUCCEEDED.

### 2026-08-22
T03: DocumentKind.showsPreview hides Source/Preview picker and Toggle Mode for json/toml/Wave B. setMode/toggle cannot enter Preview. Markdown/HTML/SVG still show the picker. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED.

### 2026-08-22
T04: JSONSyntaxProfile uses JSONScanBudget.default (2 MiB / 4096 foldables / 2048 outline / 4096 spans / 50 ms). Over budget: partial folds + warning diagnostic. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Ticket left in-progress (no visual open of a .json file; no xcodebuild test).

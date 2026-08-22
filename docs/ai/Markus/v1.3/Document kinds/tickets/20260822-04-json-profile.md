---
id: 20260822-04-json-profile
title: JSON profile
type: feature
priority: high
status: done
created: 2026-08-22
updated: 2026-08-22
closed: 2026-08-22
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

- [x] `.json` folds objects/arrays; edits save as buffer text (R5, N6).
- [x] Invalid JSON does not crash; session has a diagnostic (R5, R9).
- [x] Preview control hidden for JSON.
- [x] macOS + iOS/iPad Debug builds (N2, N3).

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

### T05: Skip Markdown preview parse on non-Markdown kinds

`FoldingSession.reparse` currently always runs `PreviewStructureCollector.collect` and `MarkdownParser().previewSpans` on the full buffer. That unbounded cmark work runs for JSON on the main thread after the typing debounce, so N2 is not met even with `JSONScanBudget`. Skip both collectors when `documentKind != .markdown` (leave `parsedPreviewBlocks` / `parsedSpans` empty). Still build `SourceMap` / `UTF16LineOffsets` and union foldable start lines for the gutter. HTML/SVG Preview is WebView (ticket 05), not substitution, so they must skip this path too.

Files: `Markus/Markus/Editor/FoldingTextView.swift`

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
Wrote implementation plan T01–T04 (scanner folds; JSONSyntaxProfile+factory; hide Preview for Source-only kinds; N2 scan budget). NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01: JSONScanner walks UTF-8 offsets; FoldID.Kind object/array; fold extent after opener line; MarkdownBlockKind.other. macOS Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: JSONSyntaxProfile wraps the scanner; SyntaxProfiles.profile(for: .json) wired. Other non-markdown kinds stay empty. macOS Debug BUILD SUCCEEDED.

### 2026-08-22
T03: DocumentKind.showsPreview hides Source/Preview picker and Toggle Mode for json/toml/Wave B. setMode/toggle cannot enter Preview. Markdown/HTML/SVG still show the picker. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED.

### 2026-08-22
T04: JSONSyntaxProfile uses JSONScanBudget.default (2 MiB / 4096 foldables / 2048 outline / 4096 spans / 50 ms). Over budget: partial folds + warning diagnostic. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Ticket left in-progress (no visual open of a .json file; no xcodebuild test).

## Review

2026-08-22 — **Important.** Controller may not mark `done`. Fix N2 (or get an explicit human defer) before closing.

Commits `3dd2c96`, `e28c4c7`, `3619d78`, `1cba070`. Messages match `{ticket-id} {task-id}: {title}`. Plan files match the diff (T03 also touched `ModeChrome.swift`, a real `setMode` entry point). R5/R9/N6 look met in code: dedicated scanner (not tree-sitter / `JSONSerialization` ranges), object/array folds, invalid input diagnoses without crashing, session `outlineItems`/`diagnostics` flow through, save remains `DocumentSave.writeUTF8`. Preview chrome hidden via `DocumentKind.showsPreview`. Notes claim macOS+iOS/iPad Debug builds; no visual open of a `.json` file.

- Important: N2 is not met. `JSONScanBudget.default` bounds only `JSONScanner`; `FoldingSession.reparse` still runs `PreviewStructureCollector.collect` and `MarkdownParser().previewSpans` on the **full** buffer for JSON (`FoldingTextView.swift:278-284`). That work is unbounded, on the main thread, after the 120 ms debounce (`FoldingTextView.swift:2306-2333`). A multi-MB `.json` can still freeze typing/open. Skip markdown preview collection when `documentKind` is not markdown (or when `!showsPreview`).
- Minor: `Engine.init` copies `Array(buffer.utf8)` before applying `maxBytes` (`JSONScanner.swift:65-68`).
- Minor: Fold extent is `openerEnd..<closerEnd` at the closer token (`JSONScanner.swift:405-407`). Correct for `},` lines; a pretty-printed `}`-only closer leaves its trailing newline visible (blank line vs fence `toEndOfLine`).
- Minor: Array outline rows are only emitted for nested `{`/`[` (`JSONScanner.swift:251-253`), not primitive elements. Compact JSON keys can share `sourceLine`, which the existing outline `ForEach` uses as `id` (`ContentView.swift:177`).
- Minor: Object recovery that stops on `}` then `break`s reports "Unclosed object" and omits the fold (`JSONScanner.swift:171-178`, `233-234`). Invalid JSON, no crash; closed-but-invalid objects are dropped.

2026-08-22 — **Minor** after T05. Controller may mark done.

`df1edc8` `20260822-04 T05: Skip Markdown preview parse on non-Markdown kinds`. `FoldingSession.reparse` now runs `PreviewStructureCollector` / `previewSpans` only when `documentKind == .markdown`. JSON/HTML pay JSONScanBudget (or later XML budget) plus SourceMap, not cmark. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeeded. Remaining items from the first review stay Minor.

### 2026-08-22
Debug: N2 fail was not the JSON scanner. `FoldingSession.reparse` always ran `PreviewStructureCollector` + `MarkdownParser.previewSpans` on the full buffer, including JSON. Adding T05 to skip that path when `documentKind != .markdown`.

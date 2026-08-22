---
id: 20260822-06-toml-profile
title: TOML profile
type: feature
priority: medium
status: in-progress
created: 2026-08-22
updated: 2026-08-22
closed:
notes: 'model_tier: standard'
parent:
depends_on:
- 20260822-02-syntaxprofile-and-fold-generalization
subtasks: []
plan_status: done
---
## Description

TOML tables and array-of-tables fold. Outline: table headers. Diagnostics on invalid TOML if cheap. Source-only.

## Acceptance criteria

- [ ] `.toml` folds tables (R8).
- [ ] Outline rows exist on the session (R9).
- [ ] macOS Debug build succeeds.

## Context

Depends on 02. R8, R9.

NO TDD. Verify by build.

## Subtasks

- [ ] TOML table folds.
- [ ] Outline + diagnostics.

## Implementation plan

Status: done
Current task: 

### T01: TOML scanner → table / array-of-tables fold extents + outline + diagnostics + budget

Byte-offset TOML scanner (not tree-sitter, not a copied CotEditor grammar). Walk UTF-8, track 1-based lines the same way `JSONScanner` / `SourceMap` do (`\n` only). At statement position, `[name]` is a table and `[[name]]` is an array-of-tables; `[…]` / `{…}` after `=` are values, not headers. Fold extent is `openerEnd..<nextHeaderLineStart` (or EOF): the header line stays visible, body lines fold, same idea as fences/JSON. Same-line / empty body is not foldable. Nested dotted keys do not add extra fold units. Inline tables and one-line arrays are not required to fold. `Block.kind` is `MarkdownBlockKind.other` so Preview substitution never treats these as fences. `FoldID.Kind` gains `table` / `arrayTable`. Outline: one row per table header (level = dotted-key segment count − 1). Cheap diagnostics (unclosed string/array/inline table, malformed header) — no crash. Cheap highlight spans for keys/strings/comments/numbers. `TOMLScanBudget` mirrors `JSONScanBudget` (2 MiB, foldable/outline/span caps, 50 ms). Over budget: stop, keep partial folds, warning diagnostic.

Files: `Markus/Markus/Syntax/TOMLScanner.swift`, `Markus/Markus/Markdown/BlockIndex.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done
### T02: TOMLSyntaxProfile + factory wiring

`TOMLSyntaxProfile.analyze` runs the scanner with `TOMLScanBudget.default` and returns `SyntaxAnalysis` (foldables, outline, diagnostics, spans). Empty / invalid TOML: no crash. `SyntaxProfiles.profile(for: .toml)` returns this profile. Other unprofiled kinds stay `EmptySyntaxProfile`. Preview chrome is already Source-only for toml (ticket 04).

Files: `Markus/Markus/Syntax/TOMLSyntaxProfile.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

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
Wrote implementation plan T01–T02 (scanner folds + budget; TOMLSyntaxProfile + factory). NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01: TOMLScanner walks UTF-8 offsets; FoldID.Kind table/arrayTable; fold extent after header line through next table header; MarkdownBlockKind.other; TOMLScanBudget 2 MiB / 50 ms. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: TOMLSyntaxProfile wraps the scanner with TOMLScanBudget.default; profile(for: .toml) returns it. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Ticket left in-progress (no visual open of a .toml file; no xcodebuild test).

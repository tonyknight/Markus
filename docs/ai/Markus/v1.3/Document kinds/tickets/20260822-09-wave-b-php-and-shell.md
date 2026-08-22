---
id: 20260822-09-wave-b-php-and-shell
title: Wave B PHP and Shell
type: feature
priority: low
status: in-progress
created: 2026-08-22
updated: 2026-08-22
closed:
notes: 'model_tier: standard'
parent:
depends_on:
- 20260822-08-wave-b-brace-languages
subtasks: []
plan_status: in-progress
current_task: T03
---
## Description

PHP: function/class/block folds only — no HTML-island folds. Shell: kind + color; optional keyword/indent folds; must degrade safely. Slip with ticket 08 if Wave A was not solid.

## Acceptance criteria

- [ ] PHP folds functions/classes/blocks, not HTML islands (R13), **or** slipped with 08.
- [ ] Shell has a kind and coloring; folds are best-effort (R13).
- [ ] macOS Debug build if implemented.

## Context

Depends on 08. R13.

NO TDD. Verify by build.

## Subtasks

- [x] PHP profile without HTML islands.
- [ ] Shell kind + color + best-effort folds.

## Implementation plan

Status: in-progress
Current task: T03

### T01: PHP brace dialect (no HTML islands) + profile

Add `BraceDialect.php`. Skip `//`, `/* */`, `#` comments (except `#[` attributes), and `'…'` / `"…"` / `` `…` `` strings; skip heredoc/nowdoc as strings. Do **not** skip slash-regex (PHP patterns live in strings). Do **not** fold tags: `<div>` and `<?php` / `<?=` are not fold units — `{` blocks only. PHP strings continue through newlines. Wire `BraceSyntaxProfile.php` and `SyntaxProfiles.profile(for: .php)`. Shell stays `EmptySyntaxProfile`. Bound scan via `BraceScanBudget.default`.

Files: `Markus/Markus/Syntax/BraceScanner.swift`, `Markus/Markus/Syntax/BraceSyntaxProfile.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done

### T02: Shell kind + color + best-effort folds + profile

`ShellScanner` + `ShellScanBudget` (same 2 MiB / 50 ms caps as brace). Highlight keywords, strings, `#` comments, numbers. Best-effort `{…}` folds for `function name {` / `name() {` groups: skip quotes and `${…}` so parameter expansion cannot steal a closer. Same-line `{ }` is not foldable. No indent folds. Unmatched `}` is ignored; over-budget stops with a warning. Must not crash on typical `.sh`. `ShellSyntaxProfile` uses `.default`; factory maps `.shell`.

Files: `Markus/Markus/Syntax/ShellScanner.swift`, `Markus/Markus/Syntax/ShellSyntaxProfile.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done

### T03: Info.plist, importer, New items, kind menus

Info.plist document types + imported UTIs for php (`public.php-script`, `php`) and shell (`public.shell-script`, `sh`/`bash`/`zsh`). Same `NSDocumentClass`. `DocumentKind.shipped` = `waveA` + `waveBBrace` + php + shell. File importer uses `shipped`. File → New PHP / New Shell. Mac Format Document Kind + iOS compact menu iterate `shipped`. Selectors + `writableTypes` include the new kinds. `showsPreview` is already false.

Files: `Markus/Markus/Info.plist`, `Markus/Markus/Document/DocumentKind.swift`, `Markus/Markus/Document/MarkusCommands.swift`, `Markus/Markus/Document/MacMainMenu.swift`, `Markus/Markus/Document/MarkdownDocument.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [ ] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-22
Wrote implementation plan T01–T03 (PHP brace dialect no HTML islands; Shell color + best-effort braces; Info.plist/New/menus). NO TDD. Verify by xcodebuild build. Not slipping.

### 2026-08-22
T01: BraceDialect.php skips //, /* */, # (not #[]), strings, heredoc. No slash-regex. No HTML/<?php folds — braces only. BraceSyntaxProfile.php wired. Shell still empty. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: ShellScanner colors keywords/strings/# comments/numbers; best-effort { } folds skip quotes and ${}. No indent folds. Unmatched } ignored. Bound 2 MiB / 50 ms. ShellSyntaxProfile wired. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

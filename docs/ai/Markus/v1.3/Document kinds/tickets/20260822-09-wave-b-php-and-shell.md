---
id: 20260822-09-wave-b-php-and-shell
title: Wave B PHP and Shell
type: feature
priority: low
status: done
created: 2026-08-22
updated: 2026-08-22
closed: 2026-08-22
notes: 'model_tier: standard'
parent:
depends_on:
- 20260822-08-wave-b-brace-languages
subtasks: []
plan_status: done
---
## Description

PHP: function/class/block folds only — no HTML-island folds. Shell: kind + color; optional keyword/indent folds; must degrade safely. Slip with ticket 08 if Wave A was not solid.

## Acceptance criteria

- [x] PHP folds functions/classes/blocks, not HTML islands (R13), **or** slipped with 08.
- [x] Shell has a kind and coloring; folds are best-effort (R13).
- [x] macOS Debug build if implemented.

## Context

Depends on 08. R13.

NO TDD. Verify by build.

## Subtasks

- [x] PHP profile without HTML islands.
- [x] Shell kind + color + best-effort folds.

## Implementation plan

Status: done
Current task: 

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
- [x] done

### T04: PHP heredoc closer accepts any non-identifier byte

`matchPHPHeredocCloser` only treated EOF / newline / `;` as the end of a heredoc. PHP 7.3+ allows `foo(<<<SQL\n…\nSQL)` so `)` / `,` after the label must close the body. Otherwise later `function`/`class` braces are swallowed. A longer identifier (`SQLX`) is still not a closer.

Files: `Markus/Markus/Syntax/BraceScanner.swift`

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
Wrote implementation plan T01–T03 (PHP brace dialect no HTML islands; Shell color + best-effort braces; Info.plist/New/menus). NO TDD. Verify by xcodebuild build. Not slipping.

### 2026-08-22
T01: BraceDialect.php skips //, /* */, # (not #[]), strings, heredoc. No slash-regex. No HTML/<?php folds — braces only. BraceSyntaxProfile.php wired. Shell still empty. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: ShellScanner colors keywords/strings/# comments/numbers; best-effort { } folds skip quotes and ${}. No indent folds. Unmatched } ignored. Bound 2 MiB / 50 ms. ShellSyntaxProfile wired. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T03: Info.plist document types + imported UTIs for php/shell; shipped = waveA + brace + php + shell; New PHP/New Shell; Mac + iOS kind menus via shipped; selectors. Ticket left in-progress (no visual open of a .php/.sh file; no xcodebuild test). macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED.

## Review

2026-08-22 — **Important.** Controller may not mark `done`. Fix PHP heredoc/nowdoc closers so a `<<<` used as a function/array argument does not swallow the rest of the buffer.

Commits `5bbbf0a` T01, `7d1d4b6` T02, `5effca4` T03. Messages match `{ticket-id} {task-id}: {title}`. Plan files match the diff (`ShellScanner.swift` / `ShellSyntaxProfile.swift` added; menus pick up php/shell via `DocumentKind.shipped`). NO TDD, as specified. Notes claim macOS+iOS/iPad Debug builds. Interleaved `20260822-08` T04 regex commit is out of this ticket’s scope.

- **Important** — PHP heredoc/nowdoc does not actually skip on ordinary PHP 7.3+ closers. `matchPHPHeredocCloser` (`BraceScanner.swift`) only accepts EOF, newline, or `;` after the label. `foo(<<<SQL\n…\nSQL)` and `[ <<<SQL\n…\nSQL, … ]` leave `after` as `)` or `,`, so the body never ends; the rest of the file is a string highlight and later `function`/`class` `{` blocks are not folded. That fails R13 “PHP folds functions/classes/blocks.” Allow any non-identifier byte after the label (the documented “additional tokens” form). Unclosed heredoc at EOF already degrades with a diagnostic — keep that.
- **Minor** — `<div>` / `<?php` / `<?=` are not fold units (braces only), which matches the plan. Residual: `{` inside HTML-island `<style>` / `<script>` still folds, and an unbalanced island `{` can steal a later PHP closer. Do not take this as a request to parse HTML islands.
- **Minor** — Shell matches the lowered bar: kind + keyword/string/`#`/number color; best-effort `{…}` folds; quotes and `${…}` skipped; same-line `{ }` not foldable; unmatched `}` ignored; 2 MiB / 50 ms warning; no indent/`if`/`fi` folds. Residual: a `'` inside a `<<EOF` body is treated as an opening quote and can swallow the rest of a typical `.sh`. Best-effort, not a crash.
- **Minor** — Ticket AC still unchecked; T03 notes no on-screen open of a `.php`/`.sh` file. Residual: human glance after the heredoc fix, not a substitute for that fix.
- **Minor** — `UTImportedTypeDeclarations` re-declares system UTIs `public.php-script` and `public.shell-script` (`Info.plist`), same pattern as ticket 08’s CSS/JS/Swift imports.

### 2026-08-22
Debug: PHP heredoc closer only accepted EOF/newline/`;`. T04 accepts any non-identifier byte so `foo(<<<SQL\n…\nSQL)` does not swallow later function/class folds.

## Review (T04)

2026-08-22 — **Minor.** Controller may mark done. Heredoc closer matches PHP 7.3+ additional tokens. Remaining items stay Minor.

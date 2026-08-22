---
id: 20260822-08-wave-b-brace-languages
title: Wave B brace languages
type: feature
priority: medium
status: done
created: 2026-08-22
updated: 2026-08-22
closed: 2026-08-22
notes: 'model_tier: premium'
parent:
depends_on:
- 20260822-04-json-profile
- 20260822-05-html-and-svg
- 20260822-06-toml-profile
subtasks: []
plan_status: done
---
## Description

CSS, JavaScript, TypeScript, Swift: brace/block folds, UTIs, New items. `.tsx` is TypeScript kind; JSX tags are not a separate fold unit. **Slip this entire ticket** if Wave A (tickets 04–06) is not solid.

## Acceptance criteria

- [x] CSS / JS / TS / Swift files fold blocks and open with the right kind (R13), **or** the ticket is explicitly slipped in Notes.
- [x] macOS + iOS/iPad Debug builds if implemented (N3).

## Context

Depends on Wave A. R13. Brace matcher or tree-sitter — choose on the plan. No CotEditor code. Judge kernel after 04–06 before starting.

NO TDD. Verify by build.

## Subtasks

- [x] Brace/block helper.
- [x] CSS, JS, TS, Swift profiles + New + UTIs.

## Implementation plan

Status: done
Current task: 

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
- [x] done
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
- [x] done

### T04: Skip JS/TS/Swift slash-regex so `{`/`}` inside `/…/` are not folds

`/` that is not `//` or `/*` currently falls through to code, so `/{/` and `/}/` steal block delimiters and break R13 function/class folds. Heuristic: start a regex when the previous significant token is not an ident/number/`)`/`]`, or when it was a prefix keyword (`return`, `typeof`, …). Skip character classes and escapes until the closing `/` plus flags. CSS is unchanged.

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
Wave A judgment (controller): tickets 01–07 are DONE. Kernel: DocumentKind + pin + New; JSON object/array folds; shared HTML/SVG tokenizer + locked WKWebView; TOML tables; inner colors; Markdown cmark skipped for non-markdown. Reviews were minors-only after N2/N5 fixes. Implement Wave B with a brace matcher (not tree-sitter). Not slipping this ticket.

### 2026-08-22
Wrote implementation plan T01–T03 (shared brace scanner + budget; CSS/JS/TS/Swift profiles + factory; Info.plist UTIs, importer, New items, kind menus). Brace matcher, not tree-sitter. NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01: BraceScanner walks UTF-8 offsets; FoldID.Kind.brace; fold extent after opener line through matching closer; MarkdownBlockKind.other; BraceScanBudget 2 MiB / 50 ms; dialects css/javascript/swift. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: BraceSyntaxProfile wraps the scanner with BraceScanBudget.default; profile(for:) maps css, javascript, typescript (JS dialect), swift. PHP/Shell stay EmptySyntaxProfile. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T03: Info.plist document types + imported UTIs for css/js/ts/swift; DocumentKind.shipped = waveA + brace kinds; importer, New CSS/JS/TS/Swift, Mac Format + iOS kind menus, writableTypes. Ticket left in-progress (no visual open of a .css/.js/.ts/.swift file; no xcodebuild test). macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED.

## Review

2026-08-22 — **Important.** Controller may not mark `done`. Do not start ticket 09. Fix JS/TS (and Swift) regex `/…/` so `{`/`}` inside a regex cannot steal block folds.

Commits `0af83c2` T01, `afd31f1` T02, `7863756` T03. Messages match `{ticket-id} {task-id}: {title}`. Plan files match the diff. Brace matcher (not tree-sitter). `.tsx` → `DocumentKind.typescript`. JSX tags are not fold units (braces only). `shipped` = Wave A + css/javascript/typescript/swift; PHP/Shell stay empty. Notes claim macOS+iOS/iPad Debug builds.

- **Important** — JavaScript/TypeScript (and Swift `/…/` literals) do not skip regex. After `/` that is not `//` or `/*`, the next `{` or `}` is treated as a block delimiter (`BraceScanner.swift` `scanCode` `/` branch, `openBrace`, `closeBraceOrInterpolation`). `function outer() { const re = /{/; … }` opens a fake brace at `/{/`; the function’s closer then pairs with that, and the real function is left unclosed (`Unclosed block`). `replace(/}/g, …)` closes the enclosing fold early. The plan skipped strings, comments, and template `${}`; regex is the remaining JS delimiter class and it breaks R13 function/class/block folds on ordinary files. A slash-regex skip (not tree-sitter) is enough.
- **Minor** — Ticket AC still unchecked; T03 notes no on-screen open of a `.css`/`.js`/`.ts`/`.swift` file. Residual: human glance after the regex fix, not a substitute for that fix.
- **Minor** — `UTImportedTypeDeclarations` re-declares system UTIs `public.css`, `com.netscape.javascript-source`, and `public.swift-source` (`Info.plist`). Wave A listed `public.json` / `public.html` only under `CFBundleDocumentTypes`. TypeScript’s imported UTI is appropriate; the three system re-imports are redundant and can confuse Launch Services.
- **Minor** — `Engine.init` copies `Array(buffer.utf8)` before applying `maxBytes` (`BraceScanner.swift` 103–107), same as JSON.

### 2026-08-22
Debug: JS/TS `/` that was not a comment was treated as code, so `/{/` stole braces. T04 skips slash-regex (and Swift `/…/` literals) using a previous-token heuristic plus prefix keywords (`return`, `typeof`, …). CSS unchanged.

## Review (T04)

2026-08-22 — **Minor.** Controller may mark done. Slash-regex skip lands before any `load` of `{`/`}` inside `/…/`. Remaining items stay Minor.

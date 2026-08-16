---
id: 20260815-04-gfm-preview-completeness
title: GFM Preview completeness
type: feature
priority: high
status: done
created: 2026-08-15
updated: 2026-08-15
closed: 2026-08-15
notes: T04 review minors-only; marking done
parent:
depends_on:
- 20260815-03-document-lifecycle
subtasks:
- id: S1
  title: Parser GFM fixture events
  status: done
- id: S2
  title: Preview attributed rendering
  status: done
- id: S3
  title: Theme tokens
  status: done
- id: S4
  title: Three-destination verify
  status: done
plan_status: done
---
## Description

Truthful GFM Preview: tables, task lists, strikethrough, footnotes, fenced
code, themed tokens. Fixture tests.

## Acceptance criteria

- [x] Preview fixture covers headings, tables, task lists, strikethrough, footnotes, fenced code
- [x] Rendering matches claimed GFM (no house dialect)
- [x] Theme tokens color Markdown elements
- [x] Math, Mermaid, and raw HTML are not first-class
- [x] Tests pass on Mac, iPhone simulator, and iPad simulator

## Context

Requirements R1, R9 tokens (picker UI is ticket 08).

## Subtasks

- [x] GFM fixture tests
- [x] Preview attributed rendering
- [x] Theme tokens
- [x] Three-destination verify

## Implementation plan

Status: done
Current task: 

### T01: Parser GFM fixture events
Keep `MarkdownParser.parse` returning heading/fence `MarkdownBlock`s so `BlockIndex` still folds. Add a sourcepos walk that emits **preview spans** (byte ranges) for GFM the fixture requires: ATX headings, tables, task-list items, strikethrough, footnotes, fenced code, plus inlines needed to paint Preview (`link`, `inlineCode`). Do not invent a second Markdown dialect; cmark-gfm remains the source of truth (N2). Footnotes stay enabled (`CMARK_OPT_FOOTNOTES` + extension).
A shared fixture file (headings, table, task list, strikethrough, footnote, fenced code) asserts those spans exist with non-empty byte ranges. Math `$x$` and a ` ```mermaid ` fence are **not** reported as first-class kinds.
Files: `Markus/Markus/Markdown/MarkdownParser.swift`, `Markus/MarkusTests/MarkdownParserTests.swift`, fixture under `Markus/MarkusTests/` as needed
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T02: Preview attributed rendering
Preview paints **themed `NSAttributedString` on the existing source buffer** (same `NSTextStorage`; disk stays full UTF-8). Do not replace the buffer with HTML, WebKit, or a second document. `FoldingSession` Preview styling uses parser spans: heading, table, task list, strikethrough, footnote, fence, link, inline code. Source mode stays monospaced raw text. Tests load the fixture in Preview and assert attributes at known ranges (e.g. strikethrough on `~~…~~`, fence token on the fenced block, heading token on the ATX line). `$x$` and mermaid fences get no math/diagram attributes. Fold hide must still work (layout fragments, not paragraph-style squash).
Files: `Markus/Markus/Markdown/` (renderer), `Markus/Markus/Editor/FoldingTextView.swift`, `Markus/MarkusTests/` preview fixture tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T03: Theme tokens
Introduce `ThemeTokens` matching the Requirements data model: `heading`, `body`, `link`, `inlineCode`, `fence`, `list`, `foldMarker`, plus colors Preview already needs (`table`, `strikethrough`, `footnote`, `background`). Ship **one default palette** used by Preview (and Source body/fence as needed). Tests: swapping a token color changes the corresponding Preview range. Do **not** build the six-theme picker UI (ticket 08).
Files: `Markus/Markus/Theme/ThemeTokens.swift` (or equivalent), renderer + `FoldingTextView` wiring, tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T04: Three-destination verify
Shared parser/preview/fold code must pass all three destinations.
Verify:
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
(also re-run macOS from T03 if needed)
Files: tests/fixtures as needed; no WebKit
- [ ] todo
- [x] done

## Notes

### 2026-08-15
T01 GREEN: previewSpans emit GFM fixture kinds; parse still returns heading/fence for BlockIndex; $x$ and mermaid are not special-cased.

### 2026-08-15
T02 GREEN: Preview paints GFM span attributes on the same NSTextStorage; folds still hide via layout fragments.

### 2026-08-15
T03 GREEN: ThemeTokens default palette; swapping heading/link recolors Preview ranges; no picker UI.

### 2026-08-15
T04 GREEN: MarkusTests TEST SUCCEEDED on iPhone 17 and iPad Pro 13-inch (M5); macOS already green from T03. Ticket left in-progress (not marked done).

## Review

- **Date:** 2026-08-15
- **Verdict:** Minor only — done
- **Verify (controller, fresh):** MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5).
- **Findings:**
  1. **Minor:** `ThemeTokens.background` is unused; canvas still uses system text/background colors (ticket 08).
  2. **Minor:** Fixture covers `$x$` and mermaid, not a raw-HTML negative case.
  3. **Minor:** T01–T03 are tests+implementation in one commit (no RED SHA).
  4. **Minor:** Frontmatter subtasks/AC were still unchecked at review (fixed on close).

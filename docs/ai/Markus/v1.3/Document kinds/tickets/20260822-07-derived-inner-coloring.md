---
id: 20260822-07-derived-inner-coloring
title: Derived inner coloring
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

Keyword / string / comment / number colors derived from existing `ThemeTokens` (body/fence/link) on non-Markdown Source. No new Appearance wells. Markdown Source stays v1.2 1:1 body styling.

## Acceptance criteria

- [ ] Non-Markdown Source shows inner colors so folded headers read as structure (R10).
- [ ] Markdown Source unchanged (R4, R10).
- [x] macOS Debug build succeeds.

## Context

Depends on 02. R10. Profiles may emit highlight spans (ticket 02).

NO TDD. Verify by build.

## Subtasks

- [x] Derive CodeColorRoles from ThemeTokens.
- [x] Apply on non-Markdown Source only.

## Implementation plan

Status: done
Current task: 

### T01: CodeColorRoles derived from ThemeTokens

Add `CodeColorRoles` with keyword / string / comment / number, constructed from existing `ThemeTokens` (no new Appearance wells, no ThemeStore persistence, no Settings UI). Mapping: keyword ← `link`, string ← `fence`, number ← `inlineCode`, comment ← `italic`. `ThemeTokens` itself is unchanged. JSON/HTML/TOML scanners already emit spans for keys/tags/table names, strings, numbers, comments — do not change scanners in this task.

Files: `Markus/Markus/Theme/CodeColorRoles.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo
- [x] done
### T02: Apply highlight spans on non-Markdown Source in applyStyling

In `FoldingSession.applyStyling`, after painting Source with `tokens.body`, if `documentKind != .markdown`, overlay `analysis.highlightSpans` using `CodeColorRoles(tokens)`. Convert every span’s utf8 `bytes` to `NSRange` in one pass via `UTF8NSRange.nsRanges` (same as `MarkdownPreviewRenderer.apply` — do not call `nsRange` per span). Build on a scratch `NSMutableAttributedString` and swap once. Markdown Source stays 1:1 body. Preview path unchanged (Markdown substitution / HTML-SVG WKWebView). Missing roles: apply whatever spans exist.

Files: `Markus/Markus/Editor/FoldingTextView.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

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
Wrote implementation plan T01–T02 (CodeColorRoles from ThemeTokens; apply highlight spans on non-Markdown Source via batched UTF8NSRange). NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01: CodeColorRoles maps keyword←link, string←fence, number←inlineCode, comment←italic. No ThemeStore or Appearance changes. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Did not run xcodebuild test.

### 2026-08-22
T02: applyStyling overlays analysis.highlightSpans on non-Markdown Source via CodeColorRoles and batched UTF8NSRange.nsRanges. Markdown Source stays body-only. Preview path unchanged. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug BUILD SUCCEEDED. Ticket left in-progress (no on-screen open of a .json/.html/.toml file; no xcodebuild test).

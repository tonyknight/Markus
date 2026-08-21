---
id: 20260820-06-expanded-tokens-in-preview
title: Expanded tokens in Preview
type: feature
priority: high
status: done
created: 2026-08-20
updated: 2026-08-20
closed: 2026-08-20
notes: 'model_tier: premium'
parent:
depends_on:
- 20260820-03-family-variant-store-and-follow-system
- 20260820-04-prebuilt-catalog
subtasks:
- id: T1
  title: Widen ThemeTokens (H1–H6, bold, italic, boldItalic; keep existing roles)
  status: done
- id: T2
  title: Preview substitution uses per-heading and emphasis colors
  status: done
- id: T3
  title: Source mode stays 1:1 with the buffer
  status: done
plan_status: done
---
## Description

`ThemeTokens` has one `heading` color; Preview sizes H1–H6 but tints them all the same. Bold/italic are font traits on the parent color. This ticket widens the struct and the Preview substitution path: independent H1–H6 colors; bold / italic / bold-italic colors (traits remain). Keep background, body, link, list, fence, inline code, table, strikethrough, footnote, fold marker. Add a `callout` field so ticket 07 can bind; painting callouts is 07.

Source mode ignores the new colors. Catalog recipes from 04 must fill the new fields. Shared code: build iOS/iPad too.

## Acceptance criteria

- [ ] Preview can show H1 a different color from H2, and bold a different color from body (R8).
- [ ] Source is unchanged as a 1:1 buffer view (architecture: Preview only).
- [ ] Existing token roles still paint.
- [ ] macOS, iPhone 17 simulator, and iPad Pro 13-inch (M5) simulator Debug builds succeed.

## Context

- Requirements: R8. `PreviewSubstitution`, `PreviewHeadingScale`, `ThemeTokens`.
- Verify: three destination Debug **builds**, then look at Preview with distinct H1/H2 and bold vs body.

## Routing

**Tier: premium.** Touches the substitution renderer every document uses. Wrong defaults will look like a broken Preview, not a missing color well.

## Subtasks

- [x] Expand `ThemeTokens` and persistence for Custom’s current keys as needed.
- [x] Drive heading and emphasis colors from substitution.
- [x] Leave Source unstyled by the new fields.
- [x] Update the twelve recipes to populate new fields.

## Implementation plan

Status: done
Current task: 

### T01: Widen ThemeTokens (H1–H6, bold, italic, boldItalic; keep existing roles)
Replace `ThemeTokens.heading` with `h1`…`h6`. Add `bold`, `italic`, `boldItalic`, and `callout`. Keep background, body, link, list, fence, inline code, table, strikethrough, footnote, fold marker. Add `headingColor(level:)` for Preview. Update Equatable. Fill all twelve `NamedThemeCatalog` recipes so H1–H6 are distinguishable within a family and bold differs from body; `callout` is stored for ticket 07, not painted. Update `CustomTheme` derived palettes the same way. Compile-fix call sites of `.heading` (`ThemeChrome` swatch/well → `h1`; `ThemeStore` custom heading applies to all six levels until per-level keys exist). Compile-fix `ThemeTokensTests` / `CustomThemeTests` (`.heading` → `.h1`); do not add tests. No Appearance page. No callout parse.
Files: `Markus/Markus/Theme/ThemeTokens.swift`, `Markus/Markus/Theme/NamedThemeCatalog.swift`, `Markus/Markus/Theme/CustomTheme.swift`, `Markus/Markus/Theme/ThemeStore.swift`, `Markus/Markus/Theme/ThemeChrome.swift`, `Markus/Markus/Markdown/PreviewSubstitution.swift`, `Markus/Markus/Markdown/MarkdownPreviewRenderer.swift`, `Markus/MarkusTests/ThemeTokensTests.swift`, `Markus/MarkusTests/CustomThemeTests.swift`
Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
from `Markus/`.
- [ ] todo
- [x] done
### T02: Preview substitution uses per-heading and emphasis colors
`PreviewElementRenderer` paints H1–H6 from `headingColor(level:)` (not one shared heading). `.strong` / `.emph` / nested both use `bold` / `italic` / `boldItalic` while keeping font traits. Other roles unchanged. Do not parse or paint GitHub alerts. `MarkdownPreviewRenderer` preview-buffer heading spans use the matching H-level color so leftover buffer attributes stay consistent.
Files: `Markus/Markus/Markdown/PreviewSubstitution.swift`, `Markus/Markus/Markdown/MarkdownPreviewRenderer.swift`
Verify: same three `xcodebuild … build` commands as T01, from `Markus/`.
- [ ] todo
- [x] done
### T03: Source mode stays 1:1 with the buffer
Source `applyStyling` continues to use only `tokens.body` (and the monospaced source font) for the whole buffer — H1–H6, emphasis, and callout are Preview-only. Extend Custom persistence keys for the new selectors (`customH1`…`customH6`, bold, italic, boldItalic, callout, plus remaining unpersisted roles so 08 can bind wells). Legacy `customHeading` remains a fallback for any heading level without its own key. No new color wells UI.
Files: `Markus/Markus/Editor/FoldingTextView.swift`, `Markus/Markus/Theme/ThemeStore.swift`
Verify: same three `xcodebuild … build` commands as T01, from `Markus/`.
- [ ] todo
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-20
T01–T03 committed. ThemeTokens is h1–h6 + bold/italic/boldItalic + callout; twelve catalog recipes fill them; Preview paints per-heading and emphasis; Source stays body-only; Custom keys persist (legacy customHeading falls back). macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeeded each task. Ticket left in-progress. No Appearance wells, no callout parse.

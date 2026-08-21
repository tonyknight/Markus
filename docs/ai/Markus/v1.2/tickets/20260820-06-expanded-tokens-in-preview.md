---
id: 20260820-06-expanded-tokens-in-preview
title: Expanded tokens in Preview
type: feature
priority: high
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: premium"
parent:
depends_on:
- 20260820-03-family-variant-store-and-follow-system
- 20260820-04-prebuilt-catalog
subtasks:
- id: T1
  title: Widen ThemeTokens (H1–H6, bold, italic, boldItalic; keep existing roles)
  status: todo
- id: T2
  title: Preview substitution uses per-heading and emphasis colors
  status: todo
- id: T3
  title: Source mode stays 1:1 with the buffer
  status: todo
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

- [ ] Expand `ThemeTokens` and persistence for Custom’s current keys as needed.
- [ ] Drive heading and emphasis colors from substitution.
- [ ] Leave Source unstyled by the new fields.
- [ ] Update the twelve recipes to populate new fields.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

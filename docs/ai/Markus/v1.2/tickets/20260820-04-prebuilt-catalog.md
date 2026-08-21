---
id: 20260820-04-prebuilt-catalog
title: Prebuilt catalog
type: feature
priority: medium
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: standard"
parent:
depends_on:
- 20260820-03-family-variant-store-and-follow-system
subtasks:
- id: T1
  title: Twelve Light/Dark recipes (Nord, Monokai, Solarized, GitHub, Catppuccin, Gruvbox)
  status: todo
- id: T2
  title: Remove Daylight, Lampblack, Fog, Parchment, Meadow, Harbor from the picker
  status: todo
- id: T3
  title: Human contrast pass on body, links, fold markers
  status: todo
---
## Description

Ship the six families × Light/Dark as original sRGB recipes inspired by the public look of those themes — not copied from a vendor file. Remove the six v1.1 Markus names from the picker. Each variant is a full `ThemeTokens` recipe for whatever the token struct is at this point (ticket 06 may widen fields later; update recipes then).

Contrast of body, links, and fold markers on the background is part of done. That is a look-at-the-window pass, not a CI contrast job.

## Acceptance criteria

- [ ] Catalog is Nord, Monokai, Solarized, GitHub, Catppuccin, Gruvbox, each Light and Dark (R4).
- [ ] Daylight, Lampblack, Fog, Parchment, Meadow, Harbor are not in the picker (R4).
- [ ] Body, links, and fold markers are readable on each background when viewed in the app (N1).
- [ ] macOS Debug build succeeds; iOS/iPad simulator builds succeed if the catalog is compiled into those targets.

## Context

- Requirements: R4, N1. Depends on 20260820-03.
- Today: `NamedThemeCatalog` / `NamedThemeID`.
- Verify: macOS Debug build; run the app and flip through variants.

## Routing

**Tier: standard.** Mostly data. Judgment is visual, not architectural. Catalog standard aliases are enough; the human contrast pass is the quality bar.

## Subtasks

- [ ] Replace `NamedThemeCatalog` with twelve family/variant recipes.
- [ ] Drop the six v1.1 names from any picker-facing API.
- [ ] Eye-check contrast in Light and Dark windows.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

---
id: 20260820-04-prebuilt-catalog
title: Prebuilt catalog
type: feature
priority: medium
status: in-progress
created: 2026-08-20
updated: 2026-08-20
closed:
notes: 'model_tier: standard'
parent:
depends_on:
- 20260820-03-family-variant-store-and-follow-system
subtasks:
- id: T1
  title: Twelve Light/Dark recipes (Nord, Monokai, Solarized, GitHub, Catppuccin,
    Gruvbox)
  status: done
- id: T2
  title: Remove Daylight, Lampblack, Fog, Parchment, Meadow, Harbor from the picker
  status: done
- id: T3
  title: Human contrast pass on body, links, fold markers
  status: todo
plan_status: done
---
## Description

Ship the six families × Light/Dark as original sRGB recipes inspired by the public look of those themes — not copied from a vendor file. Remove the six v1.1 Markus names from the picker. Each variant is a full `ThemeTokens` recipe for whatever the token struct is at this point (ticket 06 may widen fields later; update recipes then).

Contrast of body, links, and fold markers on the background is part of done. That is a look-at-the-window pass, not a CI contrast job.

## Acceptance criteria

- [x] Catalog is Nord, Monokai, Solarized, GitHub, Catppuccin, Gruvbox, each Light and Dark (R4).
- [x] Daylight, Lampblack, Fog, Parchment, Meadow, Harbor are not in the picker (R4).
- [ ] Body, links, and fold markers are readable on each background when viewed in the app (N1).
- [x] macOS Debug build succeeds; iOS/iPad simulator builds succeed if the catalog is compiled into those targets.

## Context

- Requirements: R4, N1. Depends on 20260820-03.
- Today: `NamedThemeCatalog` / `NamedThemeID`.
- Verify: macOS Debug build; run the app and flip through variants.

## Routing

**Tier: standard.** Mostly data. Judgment is visual, not architectural. Catalog standard aliases are enough; the human contrast pass is the quality bar.

## Subtasks

- [x] Replace `NamedThemeCatalog` with twelve family/variant recipes.
- [x] Drop the six v1.1 names from any picker-facing API.
- [ ] Eye-check contrast in Light and Dark windows.

## Implementation plan

Status: done
Current task: 

### T01: Twelve Light/Dark recipes (Nord, Monokai, Solarized, GitHub, Catppuccin, Gruvbox)
Replace `NamedThemeCatalog.tokens(for:variant:)` stand-ins (every family currently returns v1.1 Daylight or Lampblack) with twelve hand-authored sRGB `ThemeTokens` recipes. Switch on `ThemeFamily` × `ThemeVariant`. Each recipe fills background, heading, body, link, inlineCode, fence, list, foldMarker, table, strikethrough, footnote. Light vs dark of the same family must differ; families must differ from each other. Inspired by the public look of those themes; do not copy a vendor file. Update `ThemeTokensTests` if it still assumes shared stand-ins or the local `lampblack` name, so the test target compiles. No TDD; do not run `xcodebuild test`.
Files: `Markus/Markus/Theme/NamedThemeCatalog.swift`, `Markus/MarkusTests/ThemeTokensTests.swift`
Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```
from `Markus/`.
- [ ] todo
- [x] done
### T02: Remove Daylight, Lampblack, Fog, Parchment, Meadow, Harbor from the picker
Picker-facing titles come only from `ThemeFamily.displayName` + `ThemeVariant.displayName` (Nord Light, …). Add a single picker-title helper if needed so cards cannot show v1.1 names. Keep `ThemeSelection.parse` migration of old persistence IDs (not picker-facing). Sweep Swift UI strings for Daylight, Lampblack, Fog, Parchment, Meadow, Harbor.
Files: `Markus/Markus/Theme/NamedThemeCatalog.swift`, `Markus/Markus/Theme/ThemeChrome.swift`, `Markus/MarkusTests/ThemeTokensTests.swift`
Verify: same two `xcodebuild … build` commands as T01, from `Markus/`.
- [ ] todo
- [x] done
### T03: Human contrast pass on body, links, fold markers
Review all twelve recipes for readable body, link, and fold-marker contrast on each background (N1). Adjust sRGB values where a pair is too close; keep family identity. Window eye-check remains for the human; this task is the author-side pass so the catalog is not “polish later.”
Files: `Markus/Markus/Theme/NamedThemeCatalog.swift`
Verify: same two `xcodebuild … build` commands as T01, from `Markus/`.
- [ ] todo
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-20
T01: twelve original sRGB recipes (Nord/Monokai/Solarized/GitHub/Catppuccin/Gruvbox × Light/Dark). macOS + iPhone 17 Debug builds succeeded.

### 2026-08-20
T02: picker titles via ThemeFamily.pickerTitle; v1.1 names gone from picker API; persistence migration kept. macOS + iPhone 17 Debug builds succeeded.

### 2026-08-20
T03: author-side contrast pass on body/link/foldMarker (all pairs ≥ 4.5:1 vs background). macOS + iPhone 17 Debug builds succeeded; MarkusTests compiled via build-for-testing. Ticket left in-progress for the human window pass (N1).

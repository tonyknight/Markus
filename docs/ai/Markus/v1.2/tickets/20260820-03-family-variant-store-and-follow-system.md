---
id: 20260820-03-family-variant-store-and-follow-system
title: Family variant store and Follow System
type: feature
priority: high
status: in-progress
created: 2026-08-20
updated: 2026-08-20
closed:
notes: 'model_tier: premium'
parent:
depends_on: []
subtasks:
- id: T1
  title: Persist family, pinned variant, follow-system, named-vs-custom
  status: done
- id: T2
  title: Map named families to Light/Dark from system appearance when Follow is on
  status: done
- id: T3
  title: themeChanged on commit only, never on hover
  status: done
plan_status: done
---
## Description

Replace flat `NamedThemeID` selection with `ThemeFamily` × `ThemeVariant`, plus Follow System. Applied tokens: Custom → custom snapshot; named + follow on → catalog[family][system variant]; named + follow off → catalog[family][pinnedVariant]. Follow does not apply to Custom. `themeChanged` remains commit-only so hover cannot reparse every document.

This ticket is the store and persistence. The twelve recipes are ticket 04. The Appearance checkbox is ticket 05.

## Acceptance criteria

- [ ] Selection, follow flag, and pinned variant persist across relaunch (R5, R6).
- [ ] Follow System maps the selected family to Light/Dark from macOS appearance in every open window (R5).
- [ ] Custom is unaffected by Follow (architecture decision).
- [ ] `themeChanged` does not fire on hover (N2).
- [ ] macOS Debug build succeeds; iOS and iPad simulator Debug builds succeed (shared store).

## Context

- Requirements: R5, R6, N2. Data model `ThemeFamily` / `ThemeVariant` / `ThemeSelection`.
- Today: `ThemeStore`, `ThemeSelection.named(NamedThemeID)`.
- Verify (macOS + shared): the three `xcodebuild … build` commands in Requirements Testing.

## Routing

**Tier: premium.** Core identity of “what theme is applied.” Easy to get Follow vs pin vs Custom wrong across windows.

## Subtasks

- [x] Introduce family + variant (+ custom) in `ThemeStore` with UserDefaults round-trip.
- [x] Observe system appearance when follow is on.
- [x] Keep `themeChanged` for commits only.

## Implementation plan

Status: done
Current task: 

### T01: Persist family, pinned variant, follow-system, named-vs-custom
Replace `NamedThemeID` with `ThemeFamily` (nord, monokai, solarized, github, catppuccin, gruvbox) × `ThemeVariant` (light | dark) and `ThemeSelection` as `named(family) | custom`. Persist `selection`, `followSystem`, and `pinnedVariant` in `UserDefaults` (new keys for follow and pin; keep `markus.theme.selection` as family raw or `custom`). Migrate v1.1 IDs (`daylight`/`fog`/`parchment`/`meadow`/`harbor` → nord + light pin; `lampblack` → nord + dark pin). Applied tokens for this task: custom → custom snapshot; named + !follow → `catalog[family][pinnedVariant]`; named + follow → same formula using a live `systemIsDark` read (no observer yet). Stub `NamedThemeCatalog.tokens(for:variant:)` with daylight/lampblack stand-ins. Update `ThemePickerView`, `ThemeTokens.default`, `DocumentHost` apply/hover signatures, and MarkusTests call sites so the module still compiles. No Follow checkbox (ticket 05). No twelve palettes (ticket 04).
Files: `Markus/Markus/Theme/NamedThemeCatalog.swift`, `Markus/Markus/Theme/ThemeStore.swift`, `Markus/Markus/Theme/ThemeTokens.swift`, `Markus/Markus/Theme/ThemeChrome.swift`, `Markus/Markus/Document/DocumentHost.swift`, `Markus/MarkusTests/ThemePickerTests.swift`, `Markus/MarkusTests/ThemeTokensTests.swift`, `Markus/MarkusTests/PreviewSubstitutionTests.swift`
Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
from `Markus/`.
- [ ] todo
- [x] done
### T02: Map named families to Light/Dark from system appearance when Follow is on
Observe `NSApp.effectiveAppearance` (macOS) and `UITraitCollection` / equivalent dark-style (iOS) so a live appearance flip remaps `catalog[family][systemIsDark ? dark : light]` in every open window. Fire `themeChanged` only when `followSystem` is on and selection is named — Custom is unchanged (no broadcast, no token swap). Follow off keeps `pinnedVariant`. Toggle-off pins the variant currently showing. Isolated `ThemeStore(defaults:)` suites still work.
Files: `Markus/Markus/Theme/ThemeStore.swift`
Verify: same three `xcodebuild … build` commands as T01, from `Markus/`.
- [ ] todo
- [x] done
### T03: themeChanged on commit only, never on hover
Route selection, follow toggle, and custom edits through one private commit helper that sends `themeChanged` after the write. Hover (`beginHover`/`endHover` / `displayedTokens`) only sends `objectWillChange` so the proxy can redraw — never `themeChanged`, so open documents are not reparsed. Appearance-driven remap from T02 stays on the commit path (it is an apply, not hover).
Files: `Markus/Markus/Theme/ThemeStore.swift`
Verify: same three `xcodebuild … build` commands as T01, from `Markus/`.
- [ ] todo
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-20
T01: family×variant selection, follow/pin persistence, catalog stand-ins. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeeded.

### 2026-08-20
T02: NSApp.effectiveAppearance KVO (macOS) and colorScheme/didBecomeActive (iOS) remap named+follow; Custom skipped. Three Debug builds succeeded.

### 2026-08-20
T03: broadcastCommit is the only themeChanged sender; hover uses objectWillChange only. Three Debug builds succeeded. Plan complete; ticket left in-progress for review.

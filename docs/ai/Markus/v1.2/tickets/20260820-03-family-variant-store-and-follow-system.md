---
id: 20260820-03-family-variant-store-and-follow-system
title: Family variant store and Follow System
type: feature
priority: high
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: premium"
parent:
depends_on: []
subtasks:
- id: T1
  title: Persist family, pinned variant, follow-system, named-vs-custom
  status: todo
- id: T2
  title: Map named families to Light/Dark from system appearance when Follow is on
  status: todo
- id: T3
  title: themeChanged on commit only, never on hover
  status: todo
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

- [ ] Introduce family + variant (+ custom) in `ThemeStore` with UserDefaults round-trip.
- [ ] Observe system appearance when follow is on.
- [ ] Keep `themeChanged` for commits only.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

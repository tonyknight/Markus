---
id: 20260820-05-appearance-page-layout
title: Appearance page layout
type: feature
priority: high
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: premium"
parent:
depends_on:
- 20260820-01-settings-window-and-navigation
- 20260820-03-family-variant-store-and-follow-system
- 20260820-04-prebuilt-catalog
subtasks:
- id: T1
  title: Follow System checkbox, variant cards, Custom card
  status: todo
- id: T2
  title: Rich GFM proxy column; hover local to the page
  status: todo
- id: T3
  title: Click applies globally; hover does not restyle open documents
  status: todo
---
## Description

Build the Appearance **page** inside the Settings window: Follow System at the top; wrapping grid of one card per catalog variant plus Custom; preview column with a real Markus Preview of a rich GFM sample. Click commits via the store. Hover restyles only the proxy and lives in this view — not sticky `ThemeStore.hoverSelection` shared across windows. Close or apply clears hover.

Cards: short snippet, chip strip, name, selection check. Inner split (cards | preview) stacks vertically if the window is narrowed; sidebar does not collapse.

## Acceptance criteria

- [ ] Appearance shows Follow System, twelve variant cards plus Custom, and a proxy column with a rich sample (R3).
- [ ] Click applies to every open document; hover restyles only the proxy (R3, N2).
- [ ] Hover does not stick after close or in a second Settings window (R12).
- [ ] macOS Debug build succeeds. Launch Settings and try hover/click/Follow by eye.

## Context

- Requirements: R3, R12, N2. Depends on 01, 03, 04.
- Today: `ThemePickerView`, `ThemeChrome.sampleMarkdown` (too thin), `ThemeStore.hoverSelection`.
- Verify: macOS Debug build + run the app.

## Routing

**Tier: premium.** This is the user-visible product of the release: layout, hover isolation, Follow wiring. Easy to ship a pretty grid that still mutates the shared store on hover.

## Subtasks

- [ ] Follow System control bound to the store.
- [ ] Variant + Custom cards; click commits.
- [ ] Proxy sample: headings, paragraph, emphasis, link, inline code, fence, list, quote, table, strikethrough, footnote (callout when ticket 07 lands).
- [ ] Hover state local to the page.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

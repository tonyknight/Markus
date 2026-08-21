---
id: 20260820-05-appearance-page-layout
title: Appearance page layout
type: feature
priority: high
status: in-progress
created: 2026-08-20
updated: 2026-08-20
closed:
notes: 'model_tier: premium'
parent:
depends_on:
- 20260820-01-settings-window-and-navigation
- 20260820-03-family-variant-store-and-follow-system
- 20260820-04-prebuilt-catalog
subtasks:
- id: T1
  title: Follow System checkbox, variant cards, Custom card
  status: done
- id: T2
  title: Rich GFM proxy column; hover local to the page
  status: done
- id: T3
  title: Click applies globally; hover does not restyle open documents
  status: todo
plan_status: in-progress
current_task: T03
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

- [x] Follow System control bound to the store.
- [x] Variant + Custom cards; click commits.
- [x] Proxy sample: headings, paragraph, emphasis, link, inline code, fence, list, quote, table, strikethrough, footnote (callout when ticket 07 lands).
- [x] Hover state local to the page.

## Implementation plan

Status: in-progress
Current task: T03

### T01: Follow System checkbox, variant cards, Custom card

Replace the Appearance placeholder with a macOS `AppearanceSettingsView` bound to `ThemeStore.shared`. Put a Follow System Appearance checkbox at the top (`setFollowSystem`); disable it when selection is Custom so Follow cannot invent a second Custom variant. Below it, a wrapping `LazyVGrid` of one card per catalog variant (6 families × Light/Dark) plus a Custom card. Each card: SwiftUI snippet (not an embedded `FoldingTextView`), chip strip from existing `ThemeTokens` fields only, `ThemeFamily.pickerTitle` (or “Custom”), and a selection check via `isShowing` / `selection == .custom`. Click commits with `selectNamed` / `select(.custom)`. Do not add color wells or Use as Custom. Leave `ThemePickerView` on the iOS sheet (R13). Do not expand `ThemeTokens`.

Files: `Markus/Markus/Document/AppearanceSettingsView.swift`, `Markus/Markus/Document/SettingsWindow.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
from `Markus/`.
- [ ] todo
- [x] done

### T02: Rich GFM proxy column; hover local to the page

Expand `ThemeChrome.sampleMarkdown` to a rich GFM sample: headings, paragraph, emphasis, link, inline code, fence, list, quote, table, strikethrough, footnote. Omit GitHub alert syntax (ticket 07). Lift `ThemeProxyRepresentable` to internal and show a real Preview-mode `FoldingTextView` in a column beside the card grid. Inner split (cards | preview) uses a width threshold so it stacks vertically when the Settings window is narrowed; the left category sidebar stays a fixed-width `HStack` and does not collapse. Hover restyles only this proxy via `@State` on the Appearance view — never `ThemeStore.beginHover` / `hoverTokens`. `onDisappear` and click-apply clear that local hover so a second Settings window cannot inherit it.

Files: `Markus/Markus/Theme/ThemeChrome.swift`, `Markus/Markus/Document/AppearanceSettingsView.swift`

Verify: same macOS Debug `xcodebuild … build` as T01, from `Markus/`.
- [ ] todo
- [x] done

### T03: Click applies globally; hover does not restyle open documents

Confirm Appearance clicks go through `ThemeStore.shared` so `themeChanged` repaints every `DocumentHost` editor. Hover must not call `beginHover`/`endHover` and must not change `DocumentHost.session.editor` tokens. Document that store hover is leftover for the iOS `ThemePickerView` path only. Closing Appearance (`onDisappear`) or applying a card clears local hover. No ThemeTokens expansion.

Files: `Markus/Markus/Document/AppearanceSettingsView.swift`, `Markus/Markus/Theme/ThemeStore.swift`, `Markus/Markus/Document/DocumentHost.swift`

Verify: same macOS Debug `xcodebuild … build` as T01, from `Markus/`.
- [ ] todo
- [ ] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-20
Wrote implementation plan (T01 cards+Follow, T02 rich proxy + view-local hover, T03 global apply / no store hover). Starting T01.

### 2026-08-20
T01 done. AppearanceSettingsView: Follow System checkbox (disabled for Custom), 12 variant cards + Custom, click via ThemeStore.shared. Compat shim ThemeTokensCompatibility so 06's widened ThemeTokens still compiles. macOS Debug build succeeded.

### 2026-08-20
T02 done. Rich GFM sampleMarkdown; Appearance proxy is FoldingTextView Preview; hover is @State on the page (never ThemeStore.beginHover); inner split stacks below 540pt; onDisappear and click clear hover. macOS Debug build succeeded.

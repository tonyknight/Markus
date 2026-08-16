---
id: 20260815-08-theme-picker
title: Theme picker
type: feature
priority: medium
status: done
created: 2026-08-15
updated: 2026-08-16
closed: 2026-08-16
notes: T05 review minors-only; marking done
parent:
depends_on:
- 20260815-07-folder-tree
subtasks:
- id: S1
  title: Six named palettes
  status: done
- id: S2
  title: Custom theme controls
  status: done
- id: S3
  title: Picker UI + apply
  status: done
- id: S4
  title: Three-destination verify
  status: done
- id: S5
  title: Mac card hit-testing and visible hover
  status: done
plan_status: done
---
## Description

Six named themes, custom background + Auto / Light / Dark, live sample,
hover-preview on Mac, apply to the open document.

## Acceptance criteria

- [x] Six named built-in themes with Markdown element colors
- [x] One custom theme: background color, text style Auto / Light / Dark
- [x] Card picker with live sample; hover-preview on Mac; apply on click/tap
- [x] Names and palettes are Markus's, not copied from another product
- [x] Tests pass on Mac, iPhone simulator, and iPad simulator

## Context

Requirements R9.

## Subtasks

- [x] Six named palettes
- [x] Custom theme controls
- [x] Picker UI + apply
- [x] Three-destination verify

## Implementation plan

Status: done
Current task: 

### T01: Six named palettes
Ship **six named** Markus palettes as `ThemeTokens` (heading, body, link, inlineCode, fence, list, foldMarker, table, strikethrough, footnote, background). Original names — not copied from another product. Suggested set: **Daylight, Lampblack, Fog, Parchment, Meadow, Harbor** (rename if needed; keep six). Tests: exactly six named IDs; palettes are distinct; `FoldingTextView.setTheme` applies heading/body colors. Do not build the picker UI yet. Do not copy another app's theme names.
Files: `Markus/Markus/Theme/`, `Markus/MarkusTests/`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T02: Custom theme
One **custom** theme: user **background color** + text style **Auto / Light / Dark** (Requirements data model `customText`). Custom still fills the Markdown token set (derive heading/body/link from the text style + background). Tests: changing background and text style yields different `ThemeTokens`; Auto follows a light/dark choice from the background luminance or system style. No picker chrome yet.
Files: `Markus/Markus/Theme/`, tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T03: Card picker, live sample, apply
Settings-hosted **card picker**: live sample of GFM (reuse fixture or a short sample), apply on click/tap to the open document via existing `setTheme`. **Hover-preview on Mac** (temporary tokens while hovering; revert if not clicked). Persist the selected theme id in app storage (`UserDefaults`), not in the `.md`. Apply `ThemeTokens.background` to the editor canvas (ticket 04 leftover). Tests: select a named theme → editor tokens match; Mac hover preview changes tokens without persisting until apply; custom card applies custom tokens.
Files: `ContentView.swift` / settings + picker views, `DocumentHost` or `ThemeStore`, `FoldingTextView` background, tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T04: Three-destination verify
Shared theme code must pass all three destinations.
Verify:
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
Files: tests as needed; no tabs, no minimap
- [ ] todo
- [x] done

### T05: Mac card hit-testing and visible hover
Fix Important review:
1. Theme card samples must not steal clicks or hover. Mirror iOS: Mac `ThemeSampleView` / `FoldingTextView` in a card does not accept first responder and is not hit-testable (`hitTest` nil, or equivalent). Clicking the card still `select`s.
2. Mac hover-preview must be **visible**. Do not paint the document under a modal sheet the user cannot see. Either present Mac settings non-modally (editor remains visible while hovering cards) **or** confine hover-preview to the card sample and keep document tokens unchanged until apply. Tests: sample view is not hit-testable on Mac; selecting still applies; if document hover is kept, settings is not a blocking sheet.
Files: `ThemeChrome.swift`, `ContentView.swift`, `FoldingTextView.swift` as needed, tests
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
then iPhone 17 and iPad Pro 13-inch (M5) same as T04.
- [ ] todo
- [x] done

## Notes

### 2026-08-16
T01: six named palettes (Daylight, Lampblack, Fog, Parchment, Meadow, Harbor); NamedThemeCatalog + setTheme tests; commit 8a1d0fa.

### 2026-08-16
T02: custom background + Auto/Light/Dark; Auto follows background luminance; commit f67b5a4.

### 2026-08-16
T03: settings card picker, Mac hover-preview, UserDefaults persist, canvas background; commit 865291a.

### 2026-08-16
T04: MarkusTests TEST SUCCEEDED on iPhone 17 and iPad Pro 13-inch (M5). No code changes.

## Review

- **Date:** 2026-08-16
- **Verdict:** Important — not done
- **Verify (controller, fresh):** MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5).
- **Findings:**
  1. **Important:** Mac theme cards wrap a live `FoldingTextView` that accepts first responder / `mouseDown`, so clicks and hover never reach the SwiftUI `Button` / `.onHover`.
  2. **Important:** Hover-preview paints the document under a modal settings sheet, so the user cannot see it.
  3. **Minor:** T01–T03 are tests+code in one commit; iOS custom color persist skips sRGB convert.

### 2026-08-16
Review Important: Mac card hit-testing and visible hover-preview. T05.

### 2026-08-16
T05: Mac card samples ignore hits/first responder; settings panel non-modal so hover paints the visible editor; commit cacda54.

## Review (T05)

- **Date:** 2026-08-16
- **Verdict:** Minor only — done
- **Verify (controller, fresh):** MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5).
- **Findings:**
  1. **Minor:** Sample `hitTest` is tested on `FoldingTextView`, not the SwiftUI representable host; card click is not UI-tested.
  2. **Minor:** Nested `NavigationStack` in the Mac side pane may hoist Done into the window toolbar.
  3. **Minor (carry-over):** T01–T03 are tests+code in one commit; iOS custom color persist skips sRGB convert.

---
id: 20260820-08-use-as-custom-and-granular-controls
title: Use as Custom and granular controls
type: feature
priority: high
status: in-progress
created: 2026-08-20
updated: 2026-08-20
closed:
notes: 'model_tier: standard'
parent:
depends_on:
- 20260820-05-appearance-page-layout
- 20260820-06-expanded-tokens-in-preview
- 20260820-07-callouts
subtasks:
- id: T1
  title: Use as Custom snapshots a variant; confirm if replacing existing custom edits
  status: done
- id: T2
  title: Grouped color wells for the full selector set
  status: done
- id: T3
  title: Custom is a frozen snapshot; catalog stays immutable
  status: done
plan_status: done
---
## Description

Custom becomes clone-then-refine. **Use as Custom** copies the chosen prebuilt variant’s full token set into the custom store, selects Custom, leaves the catalog untouched. If Custom already differs from a fresh clone, confirm before overwrite. Grouped disclosures: Headings, Emphasis, Blocks, Other — wells for background, body, H1–H6, bold, italic, bold-italic, links, lists, fenced code, inline code, callouts, tables, strikethrough, footnotes, fold markers. Edits persist and `themeChanged`. Named recipes stay immutable; later catalog updates do not rebase Custom.

## Acceptance criteria

- [ ] Any prebuilt variant can be copied into Custom (R7).
- [ ] Changing H1 does not change H2; Preview shows that (R8).
- [ ] All listed selectors are editable and visible in Preview (R8).
- [ ] macOS Debug build succeeds. Run Settings and clone + tweak by eye.

## Context

- Requirements: R7, R8. Depends on 05 (page), 06 (tokens), 07 (callout well).
- Today: four optional Custom colors in `ThemeStore`.
- Verify: macOS Debug build + launch.

## Routing

**Tier: standard.** Store and tokens already exist; this is bindings, a confirm alert, and grouped wells. Product-visible but not a new renderer.

## Subtasks

- [x] Use as Custom + replace confirmation.
- [x] Grouped wells bound to expanded tokens.
- [x] Persist the full custom snapshot.

## Implementation plan

Status: done
Current task: 

### T01: Use as Custom snapshots a variant; confirm if replacing existing custom edits

Add `ThemeStore.replaceCustom(with:)` that copies a prebuilt variant’s **full** `ThemeTokens` into every custom persistence key (background, body, H1–H6, emphasis, link, list, fence, inline code, callout, table, strikethrough, footnote, fold marker), sets `selection` to `.custom`, and fires **one** `themeChanged`. Do not mutate `NamedThemeCatalog`. Add `customDiffers(from:)` via `ThemeTokens` equality against `tokens(for: .custom)`.

On `AppearanceSettingsView`, track last-clicked named family+variant (`@State`, seeded on appear from the committed named selection + `appliedVariant`). **Use as Custom** copies that source (or the currently selected named card). If Custom already differs from that clone, show a replace confirmation; otherwise snapshot immediately. Leave Follow, cards, and proxy behavior unchanged. No color wells yet. No iOS picker rewrite.

Files: `Markus/Markus/Theme/ThemeStore.swift`, `Markus/Markus/Document/AppearanceSettingsView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
from `Markus/`.
- [ ] todo
- [x] done
### T02: Grouped color wells for the full selector set

When Custom is selected, show grouped `DisclosureGroup`s under the card grid: **Headings** (H1–H6), **Emphasis** (bold, italic, bold-italic), **Blocks** (links, lists, fenced code, inline code, callouts, tables), **Other** (strikethrough, footnotes, fold markers). Always-visible wells for background and body above the groups. Each well binds to the matching `setCustom*` setter (H1 → `setCustomH1` only — changing H1 must not write H2). Defer ColorPicker writes with `DispatchQueue.main.async` like the existing iOS wells. Do not rewrite Follow/cards/proxy. Do not add these wells to `ThemePickerView` (R13).

Files: `Markus/Markus/Document/AppearanceSettingsView.swift`

Verify: same `xcodebuild` macOS Debug build as T01, from `Markus/`.
- [ ] todo
- [x] done
### T03: Custom is a frozen snapshot; catalog stays immutable

After a clone, Custom must not re-read `NamedThemeCatalog` or re-derive from `CustomTheme.tokens` for unset fields. Build committed custom tokens from the persisted snapshot when every selector key is present. Well edits keep writing only custom keys and still `themeChanged`. Named recipes remain a read-only catalog (no write API, clone copies values). Later catalog edits cannot rebase an existing Custom.

Files: `Markus/Markus/Theme/ThemeStore.swift`

Verify: same `xcodebuild` macOS Debug build as T01, from `Markus/`.
- [ ] todo
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-20
T01: replaceCustom copies full token set, selects Custom, confirms if customDiffers. macOS Debug BUILD SUCCEEDED.

### 2026-08-20
T02: Grouped wells (Headings / Emphasis / Blocks / Other) plus background and body. H1 binds setCustomH1 only. macOS Debug BUILD SUCCEEDED.

### 2026-08-20
T03: Full custom snapshot is frozen from persisted keys; catalog is read-only. macOS Debug BUILD SUCCEEDED. Ticket left in-progress.

---
id: 20260820-08-use-as-custom-and-granular-controls
title: Use as Custom and granular controls
type: feature
priority: high
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: standard"
parent:
depends_on:
- 20260820-05-appearance-page-layout
- 20260820-06-expanded-tokens-in-preview
- 20260820-07-callouts
subtasks:
- id: T1
  title: Use as Custom snapshots a variant; confirm if replacing existing custom edits
  status: todo
- id: T2
  title: Grouped color wells for the full selector set
  status: todo
- id: T3
  title: Custom is a frozen snapshot; catalog stays immutable
  status: todo
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

- [ ] Use as Custom + replace confirmation.
- [ ] Grouped wells bound to expanded tokens.
- [ ] Persist the full custom snapshot.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

---
id: 20260816-07-theme-proxy-and-global-theme
title: Theme proxy and global theme
type: feature
priority: medium
status: in-progress
created: 2026-08-16
updated: 2026-08-17
closed:
notes: ''
parent:
depends_on:
- 20260816-06-settings-surface
subtasks:
- id: T1
  title: Single proxy document below the preset + custom cards
  status: todo
- id: T2
  title: Hover-to-preview into the proxy; click-to-apply
  status: todo
- id: T3
  title: Isolate and fix card selection (suspect FoldingTextView-in-Button)
  status: todo
- id: T4
  title: App-scoped ThemeStore broadcasting to all open documents
  status: todo
---
## Description

The theme picker currently renders a miniature editor inside every card
and repaints the real document on hover — heavy and jarring — and cards
cannot currently be selected at all (root cause not yet isolated; a
suspect is `FoldingTextView` embedded inside each card's `Button`).
Separately, each `MarkdownDocument` builds its own `DocumentHost` and
therefore its own `ThemeStore`, so two Mac tabs can disagree on theme.
This ticket replaces the per-card preview with a single proxy document,
fixes selection, and makes the theme store app-scoped so a change
broadcasts to every open window and tab.

## Acceptance criteria

- [ ] Six preset cards plus custom sit above a single proxy document;
      hovering a card previews that theme in the proxy only; clicking
      applies it (R8; C.9).
- [ ] Card selection works — proven working, not assumed (R8; C.10).
- [ ] Selecting a theme applies it to **every open window and tab**
      immediately (R9; J.27).
- [ ] The choice persists across relaunch (R8).
- [ ] `ThemeStore` is a single app-scoped store, not one per
      `DocumentHost`; a change broadcasts to every open document.

## Context

- Requirements: R8, R9; Architecture component 6 "Theme store and
  picker"; Data model `Theme` (app-scoped, not per window).
- Planning doc `(2026-08-16) v1.1.md`: C.9, C.10, J.27.
- Depends on ticket 06 — the picker lives inside the settings surface's
  themes category.
- Non-goal: the six theme palettes themselves are unchanged — only the
  picker's behaviour changes.

## Subtasks

- [ ] Replace per-card miniature editors with a single proxy document
      view below the cards.
- [ ] Wire hover-to-preview (into the proxy only) and click-to-apply.
- [ ] Isolate the card-selection bug; fix it (check whether moving to a
      single proxy already dissolves it, per the planning doc's
      hypothesis).
- [ ] Promote `ThemeStore` to an app-scoped singleton; broadcast changes
      to every open `DocumentHost`.
- [ ] Persist the applied theme (`UserDefaults`) and confirm it survives
      relaunch.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

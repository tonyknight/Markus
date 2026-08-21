---
id: 20260820-09-editor-default-mode-and-about
title: Editor default mode and About
type: feature
priority: medium
status: todo
created: 2026-08-20
updated: 2026-08-20
closed:
notes: "model_tier: economy"
parent:
depends_on:
- 20260820-01-settings-window-and-navigation
subtasks:
- id: T1
  title: Persist default open mode (Preview / Source) for new and newly opened documents
  status: todo
- id: T2
  title: About page shows app name and short version from the bundle
  status: todo
---
## Description

Fill the two thin Settings categories. **Editor:** default open mode Preview (default) or Source, persisted, applied to untitled and newly opened documents — not to windows already open. **About:** app name and short version from the bundle. No other Editor settings.

## Acceptance criteria

- [ ] Editor page sets default Preview or Source; new/opened documents honor it (R10).
- [ ] About shows app name and version (R11).
- [ ] macOS Debug build succeeds. Open both pages by eye.

## Context

- Requirements: R10, R11. Depends on 01 (sidebar hosts the pages).
- Verify: macOS Debug build + launch Settings.

## Routing

**Tier: economy.** Form controls and bundle strings. No new architecture. This host may not have economy catalog models — see routing resolve; ASK if unmatched.

## Subtasks

- [ ] Persist and apply default mode on open/untitled.
- [ ] About: `CFBundleName` / `CFBundleShortVersionString` (or equivalent).

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

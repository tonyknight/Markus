---
id: 20260822-07-derived-inner-coloring
title: "Derived inner coloring"
type: feature
priority: medium
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: standard"
parent:
depends_on:
- 20260822-02-syntaxprofile-and-fold-generalization
subtasks: []
---
## Description

Keyword / string / comment / number colors derived from existing `ThemeTokens` (body/fence/link) on non-Markdown Source. No new Appearance wells. Markdown Source stays v1.2 1:1 body styling.

## Acceptance criteria

- [ ] Non-Markdown Source shows inner colors so folded headers read as structure (R10).
- [ ] Markdown Source unchanged (R4, R10).
- [ ] macOS Debug build succeeds.

## Context

Depends on 02. R10. Profiles may emit highlight spans (ticket 02).

NO TDD. Verify by build.

## Subtasks

- [ ] Derive CodeColorRoles from ThemeTokens.
- [ ] Apply on non-Markdown Source only.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

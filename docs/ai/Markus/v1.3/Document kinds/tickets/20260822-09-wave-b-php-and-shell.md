---
id: 20260822-09-wave-b-php-and-shell
title: "Wave B PHP and Shell"
type: feature
priority: low
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: standard"
parent:
depends_on:
- 20260822-08-wave-b-brace-languages
subtasks: []
---
## Description

PHP: function/class/block folds only — no HTML-island folds. Shell: kind + color; optional keyword/indent folds; must degrade safely. Slip with ticket 08 if Wave A was not solid.

## Acceptance criteria

- [ ] PHP folds functions/classes/blocks, not HTML islands (R13), **or** slipped with 08.
- [ ] Shell has a kind and coloring; folds are best-effort (R13).
- [ ] macOS Debug build if implemented.

## Context

Depends on 08. R13.

NO TDD. Verify by build.

## Subtasks

- [ ] PHP profile without HTML islands.
- [ ] Shell kind + color + best-effort folds.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

---
id: 20260822-08-wave-b-brace-languages
title: "Wave B brace languages"
type: feature
priority: medium
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: premium"
parent:
depends_on:
- 20260822-04-json-profile
- 20260822-05-html-and-svg
- 20260822-06-toml-profile
subtasks: []
---
## Description

CSS, JavaScript, TypeScript, Swift: brace/block folds, UTIs, New items. `.tsx` is TypeScript kind; JSX tags are not a separate fold unit. **Slip this entire ticket** if Wave A (tickets 04–06) is not solid.

## Acceptance criteria

- [ ] CSS / JS / TS / Swift files fold blocks and open with the right kind (R13), **or** the ticket is explicitly slipped in Notes.
- [ ] macOS + iOS/iPad Debug builds if implemented (N3).

## Context

Depends on Wave A. R13. Brace matcher or tree-sitter — choose on the plan. No CotEditor code. Judge kernel after 04–06 before starting.

NO TDD. Verify by build.

## Subtasks

- [ ] Brace/block helper.
- [ ] CSS, JS, TS, Swift profiles + New + UTIs.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

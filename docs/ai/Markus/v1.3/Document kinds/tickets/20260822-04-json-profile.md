---
id: 20260822-04-json-profile
title: "JSON profile"
type: feature
priority: high
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: premium"
parent:
depends_on:
- 20260822-02-syntaxprofile-and-fold-generalization
subtasks: []
---
## Description

Dedicated JSON parser (not tree-sitter). Object `{…}` and array `[…]` folds (opener line stays visible). Invalid JSON: no crash, diagnostic. Source-only (hide Preview). UTF-8 save of the buffer; no silent pretty-print.

## Acceptance criteria

- [ ] `.json` folds objects/arrays; edits save as buffer text (R5, N6).
- [ ] Invalid JSON does not crash; session has a diagnostic (R5, R9).
- [ ] Preview control hidden for JSON.
- [ ] macOS + iOS/iPad Debug builds (N2, N3).

## Context

Depends on 02. R5, R9, N2, N6. Do not copy CotEditor.

NO TDD. Verify by build.

## Subtasks

- [ ] JSON parser → fold extents.
- [ ] Outline rows for keys/arrays.
- [ ] Diagnostics on invalid input.
- [ ] Source-only chrome.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

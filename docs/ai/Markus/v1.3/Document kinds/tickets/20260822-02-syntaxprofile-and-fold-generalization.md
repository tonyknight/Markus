---
id: 20260822-02-syntaxprofile-and-fold-generalization
title: "SyntaxProfile and fold generalization"
type: feature
priority: high
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: premium"
parent:
depends_on:
- 20260822-01-documentkind-kernel
subtasks: []
---
## Description

`SyntaxProfile` protocol: foldables, outline rows, diagnostics, highlight spans. `FoldID` is no longer only heading/fence. Markdown profile wraps today’s `BlockIndex`. `FoldStore.repair` still loads old Markdown folds. Session exposes outline + diagnostics for v1.4 (no inspector UI).

## Acceptance criteria

- [ ] Markdown heading/fence folds still work after relaunch (R4).
- [ ] Session has outline items and diagnostics from the active profile (R9).
- [ ] macOS + iOS/iPad Debug builds succeed (N3).

## Context

Depends on 01. Requirements R4, R9. `FoldID`, `BlockIndex`, `FoldStore`, `OutlineJump`.

NO TDD. Verify by build.

## Subtasks

- [ ] `SyntaxProfile` protocol.
- [ ] Markdown profile = existing parser/index.
- [ ] Generalized `FoldID.Kind`.
- [ ] Repair loads v1.2 Markdown fold records.
- [ ] `DocumentHost`/`session` outline + diagnostics.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

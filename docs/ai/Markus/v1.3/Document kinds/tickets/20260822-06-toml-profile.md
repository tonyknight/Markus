---
id: 20260822-06-toml-profile
title: "TOML profile"
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

TOML tables and array-of-tables fold. Outline: table headers. Diagnostics on invalid TOML if cheap. Source-only.

## Acceptance criteria

- [ ] `.toml` folds tables (R8).
- [ ] Outline rows exist on the session (R9).
- [ ] macOS Debug build succeeds.

## Context

Depends on 02. R8, R9.

NO TDD. Verify by build.

## Subtasks

- [ ] TOML table folds.
- [ ] Outline + diagnostics.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

---
id: 20260822-03-kind-assignment-and-new
title: "Kind assignment and New"
type: feature
priority: high
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: standard"
parent:
depends_on:
- 20260822-01-documentkind-kernel
subtasks: []
---
## Description

Document Kind menu, Pin/Unpin persistence (only when the user pins). File → New (⌘N) stays Markdown. Explicit New JSON / HTML / SVG / TOML. Compact iOS control. No inspector pane.

## Acceptance criteria

- [ ] User can set kind; Pin survives relaunch; Unpin follows extension (R2).
- [ ] ⌘N is Markdown; New JSON creates a JSON untitled (R3).
- [ ] iOS has a compact kind control (R12).
- [ ] macOS Debug build succeeds.

## Context

Depends on 01. R2, R3, R12. Pin in app storage keyed by file identity. Untitled has no pin.

NO TDD. Verify by build.

## Subtasks

- [ ] Document Kind menu + Pin/Unpin.
- [ ] Persist pin only when explicit.
- [ ] File → New Markdown (existing) + New JSON/HTML/SVG/TOML.
- [ ] iOS compact control.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

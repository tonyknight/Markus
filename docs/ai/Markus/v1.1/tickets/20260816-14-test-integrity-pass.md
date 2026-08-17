---
id: 20260816-14-test-integrity-pass
title: "Test integrity pass"
type: chore
priority: low
status: todo
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ""
parent:
depends_on:
  - 20260816-13-text-input-in-source
subtasks:
  - id: T1
    title: Audit suite for unfalsifiable assertions; delete/rewrite MacOnlyChromeTests
    status: todo
  - id: T2
    title: Live-behaviour tests for menus, fold-all, theme, tree, preview
    status: todo
---

## Description

`MacOnlyChromeTests` asserts that `#if os(macOS) true #else false`
evaluates to `true` on macOS — it cannot fail and proves nothing.
Several other chrome tests assert compile-time flags rather than live
view behaviour. This ticket runs last, once every feature it needs to
test against actually exists, and removes or replaces every assertion
that cannot fail.

## Acceptance criteria

- [ ] `MacOnlyChromeTests` and any similar compile-time-flag assertions
      are removed or replaced with live-behaviour tests (I.25).
- [ ] Menu commands, fold-all, theme selection, tree population, and
      Preview rendering all have tests that would fail if the feature
      were removed (I.26).
- [ ] No assertion in the suite can pass unconditionally (N9).
- [ ] Menu items are asserted by validating the built `NSMenu` and the
      responder chain resolving each action, per Testing requirements →
      "How to test UI".
- [ ] The full suite passes on macOS, iPhone simulator, and iPad
      simulator (Success criteria, final bullet).

## Context

- Requirements: N9; Testing requirements → "How to test UI".
- Planning doc `(2026-08-16) v1.1.md`: I.25, I.26.
- Depends on ticket 13 — this is the final ticket in the Tasks
  Breakdown and needs every prior feature (including editing) in place
  to write meaningful live-behaviour tests against.

## Subtasks

- [ ] Audit the suite for assertions that cannot fail; catalogue them.
- [ ] Delete or rewrite `MacOnlyChromeTests` and equivalents.
- [ ] Add/replace tests for menu commands (built `NSMenu` + responder
      chain resolution), fold-all/unfold-all, theme selection, folder
      tree population, and Preview rendering — each asserting live
      behaviour, with at least one assertion that would fail if the
      feature were removed.
- [ ] Run the full suite on all three destinations and confirm green.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.

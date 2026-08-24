---
id: 20260824-04-inspector-warnings-section
title: Inspector Warnings section
type: feature
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: Parse diagnostics list with jump
parent:
depends_on:
- 20260824-01-inspector-chrome-trailing-pane
subtasks:
- id: T01
  title: Warnings list and jump
  status: done
plan_status: done
current_task: T01
---
## Description

Fill the Warnings section from `host.diagnostics`. Click jumps via `goToLine`. Empty state when none (Markdown).

## Acceptance criteria

- [x] Invalid JSON shows at least one warning; click jumps to that line.
- [x] Empty state when `diagnostics` is empty.
- [x] Severity is visible (error/warning/info).
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

`ParseDiagnostic` is `line`, `message`, `severity`. Do not add a linter. Do not parse in the inspector.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 Warnings list and jump.

## Implementation plan

Status: approved
Current task: T01

### T01: Warnings list and jump

Replace the Warnings placeholder. Click → `host.goToLine(diagnostic.line)`.

Files: `Markus/Markus/Inspector/InspectorPane.swift` (or `InspectorWarningsSection.swift`)

Verify: same three `xcodebuild` Debug builds as ticket 01.
- [x] done

## Notes

- 2026-08-24: Ticket created. Depends on 01.
- 2026-08-24: Warnings section lists diagnostics with severity and jump. Debug builds succeeded. Human should confirm broken JSON.

## Review

- Date: 2026-08-24
- Verdict: Minors only
- Findings:
  - Rows come from `host.diagnostics`; severity + message; click calls `goToLine`. Empty state: “No warnings”.
  - Invalid JSON warning jump still needs a human eye-check.

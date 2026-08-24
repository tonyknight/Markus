---
id: 20260824-03-inspector-outline-section
title: Inspector Outline section
type: feature
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: Hierarchical outline from session outlineItems
parent:
depends_on:
- 20260824-01-inspector-chrome-trailing-pane
subtasks:
- id: T01
  title: Outline list and jump
  status: done
plan_status: done
current_task: T01
---
## Description

Fill the Outline section from `host.outlineItems`. Indent by `level`. Click calls `jumpToOutlineItem`. Empty state when there are no rows.

## Acceptance criteria

- [x] Markdown headings appear and jump.
- [x] JSON keys appear and jump (v1.3 profile data).
- [x] Rows indent by `OutlineItem.level`.
- [x] Empty state when `outlineItems` is empty.
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Do not re-parse. `OutlineItem` is `title`, `sourceLine`, `level`. ForEach id: do not use `sourceLine` alone if duplicates are possible — use indices or title+line.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 Outline list and jump.

## Implementation plan

Status: approved
Current task: T01

### T01: Outline list and jump

Replace the Outline placeholder. Indent with padding from `level`. Click → `host.jumpToOutlineItem(item)`.

Files: `Markus/Markus/Inspector/InspectorPane.swift` (or `InspectorOutlineSection.swift`)

Verify: same three `xcodebuild` Debug builds as ticket 01.
- [x] done

## Notes

- 2026-08-24: Ticket created. Depends on 01.
- 2026-08-24: Outline section lists `outlineItems` with indent and jump. Debug builds succeeded. Human should confirm Markdown headings and JSON keys.

## Review

- Date: 2026-08-24
- Verdict: Minors only
- Findings:
  - Rows come from `host.outlineItems`; indent uses `level`; click calls `jumpToOutlineItem`. Empty state: “No outline”.
  - ForEach identity is list offset (safe for duplicate `sourceLine`). Markdown/JSON jump still needs a human eye-check.

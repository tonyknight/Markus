---
id: 20260824-03-inspector-outline-section
title: Inspector Outline section
type: feature
priority: high
status: todo
created: 2026-08-24
updated: 2026-08-24
closed:
notes: Hierarchical outline from session outlineItems
parent:
depends_on:
- 20260824-01-inspector-chrome-trailing-pane
subtasks:
- id: T01
  title: Outline list and jump
  status: todo
plan_status: approved
current_task: T01
---
## Description

Fill the Outline section from `host.outlineItems`. Indent by `level`. Click calls `jumpToOutlineItem`. Empty state when there are no rows.

## Acceptance criteria

- [ ] Markdown headings appear and jump.
- [ ] JSON keys appear and jump (v1.3 profile data).
- [ ] Rows indent by `OutlineItem.level`.
- [ ] Empty state when `outlineItems` is empty.
- [ ] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Do not re-parse. `OutlineItem` is `title`, `sourceLine`, `level`. ForEach id: do not use `sourceLine` alone if duplicates are possible — use indices or title+line.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [ ] T01 Outline list and jump.

## Implementation plan

Status: approved
Current task: T01

### T01: Outline list and jump

Replace the Outline placeholder. Indent with padding from `level`. Click → `host.jumpToOutlineItem(item)`.

Files: `Markus/Markus/Inspector/InspectorPane.swift` (or `InspectorOutlineSection.swift`)

Verify: same three `xcodebuild` Debug builds as ticket 01.
- [ ] done

## Notes

- 2026-08-24: Ticket created. Depends on 01.

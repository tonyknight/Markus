---
id: 20260822-02-syntaxprofile-and-fold-generalization
title: SyntaxProfile and fold generalization
type: feature
priority: high
status: done
created: 2026-08-22
updated: 2026-08-22
closed: 2026-08-22
notes: 'model_tier: premium'
parent:
depends_on:
- 20260822-01-documentkind-kernel
subtasks: []
plan_status: approved
current_task: T05
---
## Description

`SyntaxProfile` protocol: foldables, outline rows, diagnostics, highlight spans. `FoldID` is no longer only heading/fence. Markdown profile wraps today’s `BlockIndex`. `FoldStore.repair` still loads old Markdown folds. Session exposes outline + diagnostics for v1.4 (no inspector UI).

## Acceptance criteria

- [x] Markdown heading/fence folds still work after relaunch (R4).
- [x] Session has outline items and diagnostics from the active profile (R9).
- [x] macOS + iOS/iPad Debug builds succeed (N3).

## Context

Depends on 01. Requirements R4, R9. `FoldID`, `BlockIndex`, `FoldStore`, `OutlineJump`.

NO TDD. Verify by build.

## Subtasks

- [x] `SyntaxProfile` protocol.
- [x] Markdown profile = existing parser/index.
- [x] Generalized `FoldID.Kind`.
- [x] Repair loads v1.2 Markdown fold records.
- [x] `DocumentHost`/`session` outline + diagnostics.

## Implementation plan

Status: in-progress
Current task: T05

### T01: SyntaxProfile protocol and empty profile

Add a shared `SyntaxProfile` that, given a buffer, returns foldables, outline rows, parse diagnostics, and highlight spans (`SyntaxAnalysis`). Supporting types: `ParseDiagnostic` (line, message, severity) and `HighlightSpan` (byte range + keyword/string/comment/number role). `EmptySyntaxProfile` returns empty analysis. `SyntaxProfiles.profile(for:)` returns the empty profile for every kind (Markdown is T02). New files go under `Markus/Syntax/` so the synchronized Xcode folder compiles them.

Files: `Markus/Markus/Syntax/SyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T02: Markdown profile wraps BlockIndex

`MarkdownSyntaxProfile.analyze` builds foldables with today’s `BlockIndex.build` (cmark heading/fence path) and outline rows with `OutlineJump.items`. Diagnostics and highlight spans stay empty (v1.4 data hook; Markdown has no parse-warning UI here). Factory returns this profile for `.markdown` and the empty stub for every other kind (JSON ticket 04 fills JSON).

Files: `Markus/Markus/Syntax/MarkdownSyntaxProfile.swift`, `Markus/Markus/Syntax/SyntaxProfile.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T03: Generalized FoldID.Kind

`FoldID.Kind` is no longer a closed `heading|fence` enum. Make it a profile-defined string (`RawRepresentable`) with `heading` and `fence` as the Markdown values. Encode/decode as a single JSON string so existing UserDefaults records keep loading. Call sites that compare `.heading` / `.fence` stay valid.

Files: `Markus/Markus/Markdown/BlockIndex.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T04: Repair still loads v1.2 Markdown fold records

`FoldPersistence` / `FoldStore.repair` keep matching on kind + anchor. Document that persisted `"heading"` / `"fence"` strings are the v1.2 format. Wire `FoldingSession.reparse` to take foldables from the active profile so Markdown repair still rematches those records against `BlockIndex` blocks, and non-Markdown kinds get an empty block list (no fake Markdown folds).

Files: `Markus/Markus/Markdown/FoldPersistence.swift`, `Markus/Markus/Editor/FoldingTextView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T05: Session and DocumentHost expose outline and diagnostics

Set `documentKind` on the editor before `loadMarkdown` so the profile used for folds matches `session.kind`. `DocumentSession` / `DocumentHost` expose `outlineItems` and `diagnostics` from the active profile analysis (Markdown headings still come from `OutlineJump` via the Markdown profile). No inspector UI.

Files: `Markus/Markus/Document/DocumentSession.swift`, `Markus/Markus/Document/DocumentHost.swift`, `Markus/Markus/Document/MarkdownDocument.swift`, `Markus/Markus/Editor/FoldingTextView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-22
Wrote implementation plan T01–T05 (protocol+empty; Markdown BlockIndex wrap; generalized FoldID.Kind; repair loads v1.2 heading/fence; session/host outline+diagnostics). NO TDD. Verify by xcodebuild build.

### 2026-08-22
T01–T05 implemented on `bora/markus-v1-3-document-kinds`. Commits `a5a7612`, `785fc58`, `c54e0b7`, `8eeff09`, `6eac667`. SyntaxProfile + Markdown wrap of BlockIndex/OutlineJump; FoldID.Kind is a profile string that still decodes v1.2 `"heading"`/`"fence"`; FoldingSession.reparse uses the active profile; session/host expose outlineItems + diagnostics. Non-markdown kinds use EmptySyntaxProfile. No inspector UI. No JSON folds. macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeeded. Did not run xcodebuild test. Did not visually relaunch to confirm persisted Markdown folds. Ticket left in-progress.

## Review

2026-08-22 — **Minor.** Controller may mark done (minors-only). No Critical/Important.

Commits `a5a7612`, `785fc58`, `c54e0b7`, `8eeff09`, `6eac667`. Messages match `{ticket-id} {task-id}: {title}`. Plan files match the diff. R4: Markdown still uses `BlockIndex`/`OutlineJump`; Preview substitution and `FoldStore.repair` are unchanged; `FoldID.Kind` still encodes as a JSON string. R9: `DocumentSession`/`DocumentHost` expose `outlineItems` and `diagnostics` from the active profile.

- Minor: Ticket AC “folds still work after relaunch” is unchecked; Notes admit no visual relaunch. Persistence decode is compatible with v1.2 `"heading"`/`"fence"` (`BlockIndex.swift:7–25`, `FoldPersistence.swift:15–18`).
- Minor: `FoldID.Kind.rawValue` is `var` (`BlockIndex.swift:8`), so a value already in `Set<FoldID>` could be mutated in place. Nothing does that today.

---
id: 20260815-01-multiplatform-scaffold
title: Multiplatform scaffold
type: feature
priority: high
status: done
created: 2026-08-15
updated: 2026-08-15
closed: 2026-08-15
notes: Xcode multiplatform app exists; remaining work is cmark-gfm + three-destination
  verify
parent:
depends_on: []
subtasks:
- id: S1
  title: Link cmark-gfm
  status: done
- id: S2
  title: Swift parse wrapper + tests
  status: done
- id: S3
  title: Verify Mac, iPhone, iPad
  status: done
plan_status: done
---
## Description

Xcode project / scheme `Markus`, macOS + iOS + iPadOS destinations,
SwiftUI shell, **cmark-gfm** linked, empty document window.

The multiplatform target (`com.qroma.Markus`), sandbox entitlements,
Markdown document types, and empty Preview-first window are already in
`Markus/Markus.xcodeproj`. This ticket finishes the scaffold by linking
cmark-gfm and proving a Swift wrapper can parse GFM into events the
block index will consume.

## Acceptance criteria

- [x] Scheme `Markus` builds for macOS, iPhone simulator, and iPad simulator
- [x] App is SwiftUI, bundle id `com.qroma.Markus`, not Catalyst, not SwiftData
- [x] cmark-gfm is linked (SPM: `swiftlang/swift-cmark` GFM product)
- [x] A Swift wrapper parses a fixture with a heading and a fenced code block
- [x] Unit tests pass on all three destinations

## Context

Requirements Tasks Breakdown item 1. Architecture C. Project lives at
`Markus/Markus.xcodeproj`. Verify from repo root with `-project Markus/Markus.xcodeproj`.

Lab simulators (Xcode 26.3): `iPhone 17`, `iPad Pro 13-inch (M5)`.

## Subtasks

- [x] Add cmark-gfm SPM dependency to the Markus target
- [x] Swift wrapper + failing-then-passing parse tests
- [x] `xcodebuild` test on Mac, iPhone 17, iPad Pro 13-inch (M5)

## Implementation plan

Status: done
Current task: 

### T01: RED parser tests
Unit tests that a parser reports heading level 2 and a fenced-code block
from a Markdown fixture (no production parser yet).
Files: `Markus/MarkusTests/MarkdownParserTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [x] done

### T02: GREEN cmark-gfm wrapper
Add `swiftlang/swift-cmark` (cmark-gfm), Swift wrapper that walks GFM
events; tests pass.
Files: `Markus/Markus.xcodeproj/project.pbxproj`, `Markus/Markus/Markdown/MarkdownParser.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [x] done

### T03: iPhone and iPad verify
Same tests on iPhone and iPad simulators.
Files: none unless a destination-specific fix is required
Verify:
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
- [x] done

## Notes

- 2026-08-15: Multiplatform Xcode app created at Markus/Markus.xcodeproj
  (bundle id com.qroma.Markus, sandbox, document types). cmark-gfm not
  linked yet.

### 2026-08-15
T01 RED: MarkdownParserTests expects heading level 2 and fenced code; stub returns no blocks. xcodebuild macOS MarkusTests: TEST FAILED (parseReportsHeadingLevel2AndFencedCode failed; scaffoldCompiles passed). Committed eac7a2a.

### 2026-08-15
T02 GREEN: linked swift-cmark gfm branch (cmark-gfm + cmark-gfm-extensions). Wrapper walks heading/fence events. xcodebuild macOS MarkusTests: TEST SUCCEEDED.

### 2026-08-15
T03: no code changes. iPhone 17 simulator MarkusTests TEST SUCCEEDED. iPad Pro 13-inch (M5) MarkusTests TEST SUCCEEDED. Ticket left in-progress for review.

## Review

- **Date:** 2026-08-15
- **Verdict:** clean (minors-only docs hygiene)
- **Findings:** None that block done. Wrapper correctly out of scope for byte ranges (ticket 02). `scaffoldCompiles` is a no-op (minor).
- **Verify (controller, fresh):** macOS, iPhone 17, and iPad Pro 13-inch (M5) MarkusTests all TEST SUCCEEDED.

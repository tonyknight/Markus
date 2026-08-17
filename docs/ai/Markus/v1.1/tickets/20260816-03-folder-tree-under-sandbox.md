---
id: 20260816-03-folder-tree-under-sandbox
title: Folder tree under sandbox
type: bug
priority: medium
status: in-progress
created: 2026-08-16
updated: 2026-08-16
closed:
notes: ''
parent:
depends_on: []
subtasks:
- id: T1
  title: Replace path-based enumeration with security-scoped URL enumeration
  status: done
- id: T2
  title: Filter to Markdown extensions, exclude dotfiles, recurse nested folders
  status: done
- id: T3
  title: Regression test against a sandboxed fixture folder
  status: done
plan_status: approved
---
## Description

Selecting a folder yields an empty library panel. `MarkdownFolderTree.
children(of:)` enumerates with the path-based `contentsOfDirectory
(atPath:)`, which the App Sandbox (`Markus.entitlements`) denies.
Enumeration must go through the security-scoped URL instead. This is the
underlying data fix that ticket 05 (Ribbon rail and library panel)
depends on to have anything to show.

## Acceptance criteria

- [x] `MarkdownFolderTree.children(of:)` enumerates via the
      security-scoped **URL**, never a path (N7).
- [x] Opening a folder lists its Markdown files (`.md`, `.markdown`,
      `.mdown`, `.mkd`), including nested folders, excluding dotfiles and
      other file types (R6, population half).
- [x] A test exercises enumeration against a sandboxed fixture folder and
      would fail if enumeration silently returned empty (N9).

## Context

- Requirements: R6 (population half), N7.
- Planning doc `(2026-08-16) v1.1.md`: D.11.
- Ticket 05 (Ribbon rail and library panel) depends on this ticket —
  the library panel is this tree, relocated.

## Subtasks

- [x] Replace `contentsOfDirectory(atPath:)` with URL-based enumeration
      that honors the folder's security scope.
- [x] Apply the Markdown-extension and dotfile filters; recurse into
      nested folders.
- [x] Add a fixture-backed regression test asserting non-empty, correctly
      filtered results under sandbox conditions.

## Implementation plan

Status: approved
Current task: 

### T01: URL-based, security-scope-safe folder enumeration

Replace `MarkdownFolderTree`'s path-based `contentsOfDirectory(atPath:)`
and `fileExists(atPath:)` calls with URL-based FileManager APIs
(`contentsOfDirectory(at:includingPropertiesForKeys:options:)` and
`URL.resourceValues(forKeys:)`), so enumeration never touches a path
string (N7). Thread the listing call through a parameter (defaulting to
the real URL-based implementation) so the mechanism is provably
URL-based and independently testable: a test can inject a fake lister
and assert `MarkdownFolderTree.build(root:)`'s live output reflects it,
rather than the untouched real filesystem — this fails for the right
reason against today's code, which ignores any such hook and always
calls `FileManager.default` directly against the real path. Preserve
existing Markdown-extension, dotfile-exclusion, and nested-recursion
behavior (covered by the two existing tests in
`MarkdownFolderTreeTests.swift`, which must stay green throughout).

Files: `Markus/Markus/Document/MarkdownFolderTree.swift`,
`Markus/MarkusTests/MarkdownFolderTreeTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/MarkdownFolderTreeTests`

### T02: Regression test through a real sandboxed fixture folder

Add a test that builds a deeper, richer fixture (3+ nesting levels,
mixed Markdown extensions at multiple depths, a dotfile directory, a
dotfile file, a non-Markdown-only directory, an empty directory),
obtains a real security-scoped bookmark for its root exactly as
`RecentDocuments`/`FolderSession` do in production
(`.bookmarkData(options: [.withSecurityScope])`, then
`URL(resolvingBookmarkData:options:[.withSecurityScope],...)`, then
`startAccessingSecurityScopedResource()`), and asserts
`MarkdownFolderTree.build(root:)`'s live output is the full, correctly
filtered, correctly nested tree — an assertion that fails outright if
enumeration silently returns empty or leaks an excluded entry (N9).
This exercises the exact production security-scope code path end to
end, on top of T01's deterministic unit-level proof that the mechanism
is URL-based.

Files: `Markus/MarkusTests/MarkdownFolderTreeTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/MarkdownFolderTreeTests`

### Ticket-scope verify (after T02)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

## Notes

Append-only running log. Each entry dated.

### 2026-08-16
bora-debug: T02's regression test initially referenced URL.BookmarkCreationOptions/.BookmarkResolutionOptions .withSecurityScope directly and unconditionally, which is unavailable on iOS/iPadOS -- broke the iPhone 17 simulator build (N6). Root cause: should have reused RecentDocuments' existing #if os(macOS) cross-platform bookmark handling instead of reimplementing it. Fixed by rewriting the test to go through RecentDocuments.record/startAccessing (same pattern as RecentDocumentsTests), matching the real production FolderSession flow on every platform. Verified GREEN on macOS and iPhone 17 simulator after the fix.

### 2026-08-16
Ticket complete (implementation only; not marked done -- that is the controlling session's call). T01: MarkdownFolderTree.build(root:listDirectoryContents:) now enumerates exclusively via URL-based FileManager APIs (contentsOfDirectory(at:), URL.resourceValues), never atPath:/fileExists(atPath:), threaded through an injectable lister proven by a deterministic unit test (RED against the old atPath body, GREEN after the fix). T02: added a fixture-backed regression test (3+ nesting levels, mixed extensions, dotfile file+dir, non-Markdown-only dir, empty dir) driven through RecentDocuments' real bookmark/security-scope round trip, matching FolderSession's production flow; asserts full live nested/filtered output (N9). All acceptance criteria and subtasks checked. Full suite green on all three required destinations: macOS 79/79, iPhone 17 simulator 72/72, iPad Pro 13-inch (M5) simulator 72/72. Working tree clean, three commits (T01, T02, and a T02 iOS-build fix caught by bora-debug: initial test used macOS-only .withSecurityScope bookmark options unconditionally, breaking iOS/iPadOS -- fixed by routing through RecentDocuments' existing cross-platform bookmark handling). Caveat for reviewer: a real macOS App Sandbox permission denial for path-based enumeration could not be reproduced deterministically in this automated environment (confirmed empirically: temp-dir and downloads-entitled fixtures behave identically under contentsOfDirectory(atPath:) and contentsOfDirectory(at:) even with an active security scope, since those locations don't require a runtime-granted extension) -- true denial needs a folder outside all static entitlements, only reachable via a real interactive NSOpenPanel grant. T01's injectable-lister test substitutes for this: it proves the mechanism is exclusively URL-based deterministically, without depending on OS sandbox specifics.

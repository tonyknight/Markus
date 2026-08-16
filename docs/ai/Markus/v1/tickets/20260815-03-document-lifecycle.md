---
id: 20260815-03-document-lifecycle
title: Document lifecycle
type: feature
priority: high
status: in-progress
created: 2026-08-15
updated: 2026-08-15
closed:
notes: ''
parent:
depends_on:
- 20260815-02-folding-spike
subtasks:
- id: S1
  title: Open UTF-8 from URL
  status: todo
- id: S2
  title: Save, revert, dirty
  status: todo
- id: S3
  title: Recents and iOS security scope
  status: todo
- id: S4
  title: Three-destination verify
  status: todo
plan_status: in-progress
current_task: T04
---
## Description

Open/save/revert/autosave, UTF-8, recents for a single file, dirty state,
security-scoped access on iOS.

## Acceptance criteria

- [ ] Open a `.md` file from disk into the editor
- [ ] Save and revert write/restore UTF-8 source (full buffer)
- [ ] Dirty state tracks unsaved edits
- [ ] Recents remember files
- [ ] iOS uses security-scoped URLs; access fails cleanly if revoked
- [ ] Tests pass on Mac, iPhone simulator, and iPad simulator

## Context

Requirements R8 (single file), R12. Folder open is ticket 07.
Editor: `Markus/Markus/Editor/FoldingTextView.swift`. Save helper:
`DocumentSave.writeUTF8`. Do not build the folder tree.

## Subtasks

- [ ] Open/save/revert/UTF-8
- [ ] Dirty + recents
- [ ] iOS security scope
- [ ] Three-destination verify

## Implementation plan

Status: in-progress
Current task: T04

### T01: Open UTF-8 from URL
`DocumentSession` loads a file URL as UTF-8 into `NSTextStorage` and
`FoldingTextView.loadMarkdown`. Missing/unreadable files fail without
crashing. Tests use a temp `.md`.
Files: `Markus/Markus/Document/DocumentSession.swift`,
`Markus/MarkusTests/DocumentSessionTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T02: Save, revert, dirty
Save writes the **full** buffer (folded view must not shrink the file).
Revert reloads from disk. Dirty is true after an edit, false after save
or revert. Autosave can be a simple debounce or save-on-explicit-call
plus a hook — do not invent iCloud.
Files: `Markus/Markus/Document/DocumentSession.swift`,
`Markus/MarkusTests/DocumentSessionTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T03: Recents and iOS security scope
Recents store file URLs (and bookmark data on iOS). Opening from recents
starts security-scoped access when required; if the bookmark is stale,
fail cleanly (no crash). Mac can store plain URLs in tests.
Files: `Markus/Markus/Document/RecentDocuments.swift`,
`Markus/MarkusTests/RecentDocumentsTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
- [ ] todo
- [x] done
### T04: Three-destination verify
Wire `MarkusApp`/`ContentView` enough that a session can display an
opened document (fileImporter or equivalent is enough; no folder tree).
Verify:
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MarkusTests test`
and
`xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:MarkusTests test`
Files: `Markus/Markus/MarkusApp.swift`, `Markus/Markus/ContentView.swift` as needed
- [ ] todo

## Notes

### 2026-08-15
T01: DocumentSession.open loads UTF-8 into NSTextStorage and FoldingTextView; missing/invalid UTF-8 throws without crash. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-15
T02: save writes full UTF-8 via DocumentSave even when folded; revert reloads disk; dirty clears after save/revert; autosave writes if dirty. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-15
T03: Recents persist file URLs; iOS records bookmark data; startAccessing fails cleanly on stale bookmarks. macOS MarkusTests TEST SUCCEEDED.

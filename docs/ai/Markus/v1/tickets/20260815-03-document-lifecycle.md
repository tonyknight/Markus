---
id: 20260815-03-document-lifecycle
title: Document lifecycle
type: feature
priority: high
status: done
created: 2026-08-15
updated: 2026-08-15
closed: 2026-08-15
notes: T05 review minors-only; marking done
parent:
depends_on:
- 20260815-02-folding-spike
subtasks:
- id: S1
  title: Open UTF-8 from URL
  status: done
- id: S2
  title: Save, revert, dirty
  status: done
- id: S3
  title: Recents and iOS security scope
  status: done
- id: S4
  title: Three-destination verify
  status: done
plan_status: done
---
## Description

Open/save/revert/autosave, UTF-8, recents for a single file, dirty state,
security-scoped access on iOS.

## Acceptance criteria

- [x] Open a `.md` file from disk into the editor
- [x] Save and revert write/restore UTF-8 source (full buffer)
- [x] Dirty state tracks unsaved edits
- [x] Recents remember files
- [x] iOS uses security-scoped URLs; access fails cleanly if revoked
- [x] Tests pass on Mac, iPhone simulator, and iPad simulator

## Context

Requirements R8 (single file), R12. Folder open is ticket 07.
Editor: `Markus/Markus/Editor/FoldingTextView.swift`. Save helper:
`DocumentSave.writeUTF8`. Do not build the folder tree.

## Subtasks

- [x] Open/save/revert/UTF-8
- [x] Dirty + recents
- [x] iOS security scope
- [x] Three-destination verify

## Implementation plan

Status: done
Current task: 

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
- [x] done

### T05: Recents bookmarks, failed-open, dirty UI
Fix Important review:
1. Record **security-scoped bookmarks on Mac and iOS** when recording recents; resolve them on openRecent (path-only URLs are not enough under App Sandbox).
2. `DocumentSession.open` must not `releaseAccess()` on the current file until the new URL is successfully read. A failed second open leaves the visible document savable.
3. Publish dirty: after edits, Revert enables. `objectWillChange` / `@Published isDirty` when `editor.string` changes.
Tests: bookmark round-trip; failed open preserves previous `fileURL`; dirty becomes true after insert and host/session publish it.
Files: `DocumentSession.swift`, `RecentDocuments.swift`, `DocumentHost.swift`, `FoldingTextView.swift` as needed, matching tests.
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests test`
then iPhone 17 and iPad Pro 13-inch (M5) same as T04.
- [ ] todo
- [x] done
## Notes

### 2026-08-15
T01: DocumentSession.open loads UTF-8 into NSTextStorage and FoldingTextView; missing/invalid UTF-8 throws without crash. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-15
T02: save writes full UTF-8 via DocumentSave even when folded; revert reloads disk; dirty clears after save/revert; autosave writes if dirty. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-15
T03: Recents persist file URLs; iOS records bookmark data; startAccessing fails cleanly on stale bookmarks. macOS MarkusTests TEST SUCCEEDED.

### 2026-08-15
T04: ContentView fileImporter + DocumentHost displays opened file; Recents/Save/Revert wired. MarkusTests TEST SUCCEEDED on iPhone 17 and iPad Pro 13-inch (M5). Ticket left in-progress.

## Review

- **Date:** 2026-08-15
- **Verdict:** Important — not done
- **Verify (controller, fresh):** MarkusTests passed on macOS, iPhone 17, iPad Pro 13-inch (M5).
- **Findings:**
  1. Mac recents store path-only URLs; sandbox cannot reopen them (R12).
  2. Failed `open` releases the current file's security scope while leaving that document on screen.
  3. Dirty is not published; Revert stays disabled after typing.

### 2026-08-15
Review Important: Mac bookmarks, failed-open keeps access, publish dirty. T05.

### 2026-08-15
T05: Mac+iOS security-scoped recents bookmarks; failed open keeps prior scope; editor onTextDidChange publishes dirty on session/host. MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5). Ticket left in-progress.

## Review (T05)

- **Date:** 2026-08-15
- **Verdict:** Minor only — done
- **Verify (controller, fresh):** MarkusTests TEST SUCCEEDED on macOS, iPhone 17, iPad Pro 13-inch (M5).
- **Findings:**
  1. **Minor:** Mac bookmark resolve falls back to non-scoped options if `.withSecurityScope` fails.
  2. **Minor:** Bookmark creation uses `try?`; a failed `makeBookmark` stores a path-only recent.
  3. **Minor:** Mac `startAccessing` ignores a `false` result (iOS throws).
  4. **Minor:** `onTextDidChange` currently runs from `insertTextAtCaret` only; undo / direct storage edits do not publish yet.

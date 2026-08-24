---
id: 20260824-05-html-preview-sandbox-serve-via-app-scheme
title: HTML Preview sandbox serve via app scheme
type: bug
priority: high
status: in-progress
created: 2026-08-24
updated: 2026-08-24
closed:
notes: loadFileURL is rejected outside the app sandbox
parent:
depends_on: []
subtasks:
- id: T01
  title: Serve Preview HTML through WKURLSchemeHandler
  status: done
plan_status: approved
current_task: T01
---
## Description

HTML Preview is blank. WebKit logs:

`Could not create a sandbox extension for '/Users/knight/Documents/Repo/dianabelenky'`
`WebPageProxy::Ignoring request to load this main resource because it is outside the sandbox`

`loadFileURL` + `allowingReadAccessTo` cannot hand WebContent a user folder. Pasteboard / launchservicesd noise is unrelated.

Serve the live buffer from the app process via a custom URL scheme. Sibling CSS/JS/images are read by the app (which already has Open Folder / file access) and returned to WebContent.

## Acceptance criteria

- [ ] Opening a saved HTML file in Preview shows the page (not a blank WebView).
- [ ] Relative CSS, scripts, and images load when the folder is accessible (Open Folder, or the document directory).
- [ ] Remote `http`/`https` assets still load.
- [ ] JavaScript runs.
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 Serve Preview HTML through WKURLSchemeHandler.

## Implementation plan

Status: approved
Current task: T01

### T01: Serve Preview HTML through WKURLSchemeHandler

Do not call `loadFileURL` on the user’s path. Register `markushtml` on the WKWebViewConfiguration used at init. The handler serves the live buffer for the current document path and maps other paths under `resourceRoot` (`folderSession.rootURL` when present, else the file’s directory). Allow http/https; remap `file://` navigations onto the scheme when they sit under that root.

Files: `Markus/Markus/Preview/LockedHTMLPreview.swift`, `Markus/Markus/ContentView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

## Notes

- 2026-08-24: Human logs from Preview of `dianabelenky`. Branch `bora/markus-v1-3-html-preview-scheme`. Origin: `main`.
- 2026-08-24: T01 implemented. Debug builds succeeded. Waiting on in-app Preview of `dianabelenky`.

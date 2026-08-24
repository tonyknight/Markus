---
id: 20260824-02-v1-3-punch-list-round-2
title: v1.3 punch list round 2
type: bug
priority: high
status: in-progress
created: 2026-08-24
updated: 2026-08-24
closed:
notes: Focus after New picker; HTML/SVG Preview WebKit sandbox
parent:
depends_on: []
subtasks:
- id: T01
  title: Focus editor after New picker
  status: done
- id: T02
  title: HTML Preview WebKit sandbox
  status: todo
- id: T03
  title: SVG Preview WebKit sandbox
  status: todo
plan_status: approved
current_task: T02
---
## Description

Second punch list after visual testing of 20260824-01. New-document picker leaves the editor without a caret. HTML and SVG Preview fail inside the Mac sandbox (ShareMenu prefs / WebContent process never starts).

## Acceptance criteria

- [ ] After File → New and Create in the type picker, Source has a blinking caret and typing inserts. Launch untitled (no picker) still works.
- [ ] HTML Preview renders the buffer in the locked WKWebView. Navigation and script stay off. Subresource URL loads still blocked.
- [ ] SVG Preview renders the buffer (inline SVG in a minimal HTML shell). Same lockdown.

## Context

Worktree: `.worktrees/v1.3-punch-list-2` on `bora/markus-v1-3-punch-list-2`. Origin: `main`. NO TDD. Gate is xcodebuild Debug build.

Issue 6: the picker is an `NSPanel` that becomes key (`makeKeyAndOrderFront`). Closing it and calling `openUntitledDocument` in the same turn leaves the new window without key status, so `FoldingTextView` never becomes first responder (caret does not blink; keys beep). Launch untitled skips the panel, so it works.

Issues 7–8: `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO` and no `network.client` entitlement. WKWebView still needs the WebContent/network helper for `loadHTMLString`. Symptoms: CFPrefs `com.apple.ExtensionsPreferences.ShareMenu` and `RBSAssertionErrorDomain` "target process does not exist". Policy N5 stays: JS off, `baseURL` nil, content rules + navigation delegate. The entitlement is for WebKit's process, not for fetching the user's page.

`WKContentRuleListStore.default()` may also sit outside the container; use a store under Caches. Keep fail-closed if rules never compile.

## Subtasks

- [x] T01 Focus editor after New picker.
- [ ] T02 HTML Preview: WebKit sandbox + content-rule store in container.
- [ ] T03 SVG Preview: XML prolog strip + same WebKit path.

## Implementation plan

Status: approved
Current task: T01

### T01: Focus editor after New picker

Close the picker, then on the next run-loop turn create the untitled document and `makeKeyAndOrderFront` its window. Stop treating the picker as a floating key panel that outlives Create (`isFloatingPanel = false`). `FoldingTextView` becomes first responder when its window is key and Source is active (do not steal from an `NSTextField` / field editor).

Files: `Markus/Markus/Document/NewDocumentKindPicker.swift`, `Markus/Markus/Document/MarkdownDocument.swift`, `Markus/Markus/Editor/FoldingTextView.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```
- [x] done

### T02: HTML Preview WebKit sandbox

Set `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` on the Markus macOS Debug/Release settings and add `com.apple.security.network.client` to `Markus.entitlements`. Point `WKContentRuleListStore` at a Caches subdirectory, not `default()`. Keep JS off, `baseURL` nil, load only when rules are ready and Preview is visible, fail-closed if compile fails. Navigation delegate still cancels `http`/`https`/`file`.

Files: `Markus/Markus.xcodeproj/project.pbxproj`, `Markus/Markus/Markus.entitlements`, `Markus/Markus/Preview/LockedHTMLPreview.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo

### T03: SVG Preview wrapper

Strip an XML declaration / SVG doctype before wrapping in the HTML shell so WebKit is not asked to parse `<?xml` inside `<body>`. Same locked load path as HTML. Do not loosen content rules.

Files: `Markus/Markus/Preview/LockedHTMLPreview.swift`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [ ] todo

## Notes

- 2026-08-24: Ticket created. Worktree `.worktrees/v1.3-punch-list-2`, branch `bora/markus-v1-3-punch-list-2`.
- 2026-08-24 T01: Picker closes then creates untitled on the next turn; document window is made key; FoldingTextView takes first responder when its window is key. macOS Debug BUILD SUCCEEDED.

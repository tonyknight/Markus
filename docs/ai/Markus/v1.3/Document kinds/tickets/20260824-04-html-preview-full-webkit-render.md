---
id: 20260824-04-html-preview-full-webkit-render
title: HTML Preview full WebKit render
type: feature
priority: high
status: done
created: 2026-08-24
updated: 2026-08-24
closed: 2026-08-24
notes: Product override of N5 — Preview must render like Safari
parent:
depends_on: []
subtasks:
- id: T01
  title: Full WKWebView render for HTML Preview
  status: done
plan_status: approved
current_task: T01
---
## Description

HTML Preview is still not a useful render. Product decision: hand the document to WKWebView the way Safari does — script on, local folder access, CSS/JS/images/fonts/network subresources. A locked buffer-only preview has almost no value.

## Acceptance criteria

- [x] Saved HTML Preview runs page JavaScript.
- [x] Relative CSS, scripts, images, and fonts resolve against the document’s folder (`loadFileURL` + `allowingReadAccessTo`).
- [x] Remote `http`/`https` linked assets load.
- [x] In-page link clicks navigate inside Preview (same WebView). `target=_blank` loads in that WebView, not a new window.
- [x] Unsaved buffer still previews (`document.write` into the `file://` origin; no sibling file written into the user’s folder).
- [x] SVG Preview uses the same full-render path (file URL / current buffer).
- [x] macOS + iPhone 17 + iPad Pro 13-inch (M5) Debug builds succeed.

## Context

Replaces N5 for HTML/SVG Preview. Round 3 still used `loadHTMLString`, JS off at configuration construction (later assignment hits a copy), and cancelled link navigations. Safari uses `loadFileURL(_:allowingReadAccessTo:)`.

NO TDD. Gate is xcodebuild Debug build.

## Subtasks

- [x] T01 Full WKWebView render for HTML Preview.

## Implementation plan

Status: approved
Current task: T01

### T01: Full WKWebView render for HTML Preview

Enable JavaScript on the configuration used to construct the WKWebView (never on `webView.configuration`, which is a copy). Do not install the content blocker.

For an opened file, `loadFileURL` + `allowingReadAccessTo` the document directory — that is the Safari/sandbox API for sibling CSS/JS/images. Staging HTML in Caches cannot grant WebContent that folder.

Live (including unsaved) buffer: install a document-start user script that `document.write`s the current HTML into that `file://` origin, so relative URLs still resolve against the opened file. Later buffer updates use `evaluateJavaScript` on the same origin. Untitled documents stay `loadHTMLString`.

Allow http/https/file/data/blob navigations; `createWebView` loads in the same view. Link clicks pause live-buffer injection until Preview is hidden and shown again. ATS: `NSAllowsArbitraryLoadsInWebContent` so http assets work on iOS.

Files: `Markus/Markus/Preview/LockedHTMLPreview.swift`, `Markus/Markus/Info.plist`

Verify:
```
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```
- [x] done

## Notes

- 2026-08-24: Ticket created. Branch `bora/markus-v1-3-html-full-preview`. Origin: `main`.
- 2026-08-24: T01 implemented. Debug builds succeeded (macOS, iPhone 17, iPad Pro 13-inch M5). In-app Preview still needs a human check: open an HTML file with sibling CSS/JS/images, flip to Preview, confirm it looks like Safari. Untitled HTML has no folder, so relative assets will still miss.
- 2026-08-24: Human shipped to main. Closing ticket.

## Review

2026-08-24 — shipped. Verify: macOS Debug **BUILD SUCCEEDED**. Human requested merge/push to main.

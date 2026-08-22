---
hierarchy:
- Markus
- v1.4
- Inspector
last_reviewed: 2026-08-22
focus: "Document inspector, outline, and parse warnings — Markus chrome, CotEditor as behavior reference"
routing: true
routing_cache:
  cursor:
    premium: cursor-grok-4.6-high
    standard: grok 4.6
    economy: gemini-3.7-flash
depends_on: Markus/v1.3/Document kinds
---

# Markus v1.4 — Inspector

v1.3 gives Markus document kinds and folding for a small language list. Navigation still lives in a toolbar Outline menu (headings only) and a left library folder tree. CotEditor’s right-hand inspector — document metadata, a hierarchical outline, and warnings — is the product reference for this release. We implement our own pane on the existing ribbon/split, not theirs.

This briefing is the basis for `(2026-08-22) Inspector Requirements.md`. Architecture is **not** agreed until that conversation happens. v1.3’s `SyntaxProfile` outline/diagnostic **data** is a dependency; do not invent a second outline model here.

## Background

Markus already computes Markdown heading `OutlineItem`s (`OutlineJump`) and jumps even when a heading is folded. That list is a menu on iOS and a toolbar control on Mac. It does not show JSON keys, HTML elements, or Swift functions, and it does not show parse errors.

Folding without an outline does not scale once documents are trees (JSON, HTML). An inspector that **mirrors foldable nodes** is the natural next chrome: click a row, jump, optionally fold. Warnings (invalid JSON, unclosed tag) belong next to that list because they come from the same parse.

CotEditor ([coteditor/CotEditor](https://github.com/coteditor/CotEditor), Apache 2.0) is cited for **what the pane contains**, not for SwiftUI/AppKit layout code.

## What's in, at a glance

| Area | v1.2 / v1.3 | v1.4 |
|---|---|---|
| Outline | Toolbar/menu of Markdown headings | Hierarchical outline of the current kind’s foldable nodes |
| Document info | None | Filename, kind, encoding/line ending if we have them, counts |
| Warnings | None | Parse diagnostics from the kind’s profile (not ESLint/SwiftLint) |
| Placement | — | A persistent inspector (recommended: trailing split, not a sheet) that does not unmount the editor |

## Goals

- Add an inspector the user can show/hide without tearing down `FoldingTextView` (same lesson as v1.2 Settings).
- **Outline** lists the current document’s foldable structure (headings for Markdown; objects/arrays for JSON; elements for HTML/SVG; etc.), indent by depth, jump on click, stay in sync when the buffer changes (debounced).
- **Document** section: name, `DocumentKind`, and whatever metadata we already know (line count, UTF-8). Changing kind here should call the same override as v1.3’s type assignment.
- **Warnings** section: parse errors/warnings from the active profile, jump to line. Empty state when the document is valid.
- Markdown heading outline remains correct. Existing Outline toolbar may become a jump shortcut into this pane or stay as a compact menu — decide in Requirements.
- iOS: inspector must not be Mac-only data. Chrome can be a sheet or a trailing column on iPad; iPhone can keep a compact outline.

## Non-goals

- Copying CotEditor’s inspector view controllers, outline cell code, or issue UI.
- Language-server diagnostics, build errors, or running SwiftLint/ESLint/PHPStan.
- A plugin API for third-party linters.
- File-browser replacement. The left library folder tree stays the library. Inspector is about the **current document**.
- Minimap redesign, find-in-folder, or git blame.
- Implementing document kinds (that is v1.3). If v1.3 has only Markdown+JSON, the inspector still has to work for those two.

## Target users

People who fold a large JSON or HTML file and need a map, not only disclosure triangles in the gutter. People who pasted invalid JSON and need the parse error without opening Console.

## User stories

- As a developer, I want an outline of JSON keys so I can jump to `"dependencies"` without scrolling a folded tree.
- As a developer, I want a warning when JSON is invalid, with a line jump, so I can fix it in place.
- As a Markdown reader, I want the heading outline to live in the same inspector as JSON, so the chrome is one place.
- As a Mac user, I want to hide the inspector and keep the editor mounted (v1.2 Settings lesson).

## Constraints

- Depends on v1.3 profiles exposing outline rows and diagnostics. If v1.3 is not done, this project can still ship a Markdown-only inspector, then light up other kinds when profiles exist — Requirements must pick one.
- Do not swap `ContentView` to a different root when the inspector opens.
- Same `xcodebuild` Debug build gate as v1.2/v1.3 when shared code changes.

## Success criteria

- Inspector visible on macOS without unmounting the editor.
- Outline jump works for Markdown headings and for at least one non-Markdown kind that v1.3 shipped.
- A broken JSON document shows at least one warning that jumps to the failure.
- Hidden inspector does not change fold state or caret.

## Architecture options (to discuss)

**A. Trailing SwiftUI inspector in the document split (recommended).** Sibling of `FoldingTextView`, like the library panel on the left. Tabs or sections: Document / Outline / Warnings. Uses `session` outline + diagnostics. Does not collapse the left library.

**B. Reuse the left library column** to host inspector modes. Saves width; fights with folder navigation. Easy to get wrong on iPad.

**C. CotEditor-like dedicated NSViewController inspector.** Heavier AppKit; fights SwiftUI document chrome. Not our style unless the split is proven insufficient.

Recommendation: **A**.

## Relationship to v1.3

Do not start execute on this board until v1.3 Requirements (and ideally Wave A) exist, unless we explicitly scope v1.4 to Markdown-only chrome first. The briefing `depends_on` is informational; bora tickets will use `depends_on` when both boards have tickets.

## Open questions

- One inspector column with sections, or three tabs?
- Does changing document kind live in the inspector, a File menu, or both?
- iPhone: sheet vs not shipping inspector chrome until iPad/Mac?

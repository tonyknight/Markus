---
hierarchy:
- Markus
- v1
last_reviewed: 2026-08-15
focus: "Architecture C + own NSTextLayoutManager for folds"
---

# v1 Requirements

Product intent lives in `(2026-08-15) v1.md`. This file is the
agreed architecture, testable requirements, and the Tasks Breakdown that
becomes tickets. Implementation plans are written **on each ticket**, not
here.

Architecture choice: **C** — native Apple UI, custom TextKit 2 editor,
**cmark-gfm** parser, Swift block index. No Rust unless a spike proves we
need it.

## Overview

Markus v1 is a native Markdown app for macOS, iOS, and iPadOS. It opens
plain files (or a folder of Markdown files), defaults to Preview, and can
fold heading sections and fenced code blocks in Preview and Source. Save
always writes the full, unfolded document.

## Goals

- Truthful GitHub Flavored Markdown preview (CommonMark plus tables, task
  lists, strikethrough, footnotes).
- Fold headings and fenced code in Preview and Source on every platform;
  shared fold state; disk stays unfolded.
- Exclusive Source or Preview (never side-by-side); default Preview.
- Open a single Markdown file or a folder; folder tree is Markdown-only.
- Six named themes plus one custom (background + Auto / Light / Dark text).
- Mac: line numbers in both modes, tabs, fold-aware minimap.
- iPhone / iPad: optional line numbers, slim fold gutter, no tabs, no
  required minimap.

## Non-goals

As in the planning file: no split view, PKM, AI, plugins, key remap, math,
Mermaid, first-class raw HTML preview, Windows/Linux, 180-language IDE,
multi-cursor, project search, PDF/RTF export, or list/quote/`#region`
folding as a v1 commitment.

## Architecture

### Stack

| Layer | Choice |
|---|---|
| App chrome | SwiftUI (settings, tree, theme picker, iOS slider, navigation) |
| Mac documents / tabs | `NSDocument` + tabbed windows hosting the editor |
| iOS / iPad document | One document on screen; security-scoped URLs / bookmarks |
| Editor view | Custom **TextKit 2** view that **owns** `NSTextLayoutManager` (not stock `NSTextView`/`UITextView` fragment callbacks) |
| Parser | **cmark-gfm** (C), GFM extensions enabled, Swift wrapper |
| Block index + folds | Swift, derived from parser events |
| Buffer | `NSTextStorage` (rope / mmap only if a later spike proves we need them) |
| Preview drawing | Parser events → themed `NSAttributedString` in the same text view |
| Persistence of UI state | App storage (folds, theme, recents, line-number visibility). Never rewrite the `.md` |

Minimum OS (v1 floor): **macOS 14**, **iOS 17**, **iPadOS 17** — TextKit 2 plus
SwiftUI that can host this chrome. Lower only if a later decision reopens this.

### Components

1. **App shell** — SwiftUI. Mac title-bar Source / Preview controls. iPhone
   and iPad: slider (or equivalent) into Source. Settings host the theme
   picker. No dual pane.
2. **Document session** — The open file’s URL, text, dirty flag, encoding
   (UTF-8), autosave, revert. Optional **folder session**: root URL,
   security-scoped bookmark, tree of Markdown URLs.
3. **Parser** — cmark-gfm walk of the buffer. Emits events for blocks and
   inlines. GFM: tables, task lists, strikethrough, footnotes.
4. **Block index** — Ordered `Block` records: kind (heading level, fenced
   code, other), source byte range, source line range, whether foldable,
   fold extent (heading: through next same-or-higher heading; fence: body
   after the opening fence). Rebuilt when the buffer changes (debounced on
   the typing path).
5. **Fold store** — Set of folded block identities for the current file
   (stable enough across edits: kind + start line, with repair on rebuild).
   Shared by Preview and Source. Persisted per file in app state.
6. **Markus text view** — A custom view that **owns** `NSTextContentStorage` +
   `NSTextLayoutManager` + `NSTextContainer` and implements
   `NSTextLayoutManagerDelegate.textLayoutFragmentFor` so folded extents
   become zero-height / placeholder **layout fragments**. Do **not** hide
   folds by mutating paragraph styles on `NSTextStorage`. Stock
   `NSTextView` / `UITextView` may wrap editing later, but they are not
   the layout owner. Source paints the raw buffer. Preview paints
   attributed GFM. Gutter: source line numbers (Mac always; iOS optional)
   and fold controls (always, including a slim rail when numbers are off).
7. **Theme store** — Six named palettes (background + Markdown element
   colors, including fold markers). One custom: background color + text
   style Auto / Light / Dark. Live sample document in settings.
8. **Folder tree** — Nested folders; files with extensions `.md`,
   `.markdown`, `.mdown`, `.mkd` only; no dotfiles.
9. **Mac-only chrome** — Tabs (`NSDocument` tabbing). Minimap of the
   current mode that hides or compresses folded ranges.
10. **QoL services** — Outline (headings from the index), find/replace
    (must search the full buffer, not only visible fragments), go-to-line,
    status bar, zoom, keyboard shortcuts.

### Data model

```text
Document
  url: URL?
  text: NSTextStorage          // full source, always
  dirty: Bool
  mode: source | preview       // default preview
  folds: Set<FoldID>           // view state
  showLineNumbers: Bool        // Mac: always true; iOS: user pref

FolderSession?
  root: URL
  bookmark: Data
  tree: [TreeNode]             // dirs + markdown files only

Block
  id: FoldID
  kind: heading(UInt8) | fence | other
  bytes: Range<Int>
  lines: Range<Int>
  foldExtent: Range<Int>?      // source bytes hidden when folded

Theme
  id: named(String) | custom
  background: Color
  tokens: heading, body, link, inlineCode, fence, list, foldMarker, …
  customText: auto | light | dark
```

The file on disk is `text` only. Folds, mode, theme, and recents are not
Markdown.

### Key flows

**Open file.** Resolve URL (security scope on iOS). Load UTF-8 into
`NSTextStorage`. Parse → block index. Restore folds if app state has them.
Show **Preview**. Tree hidden or empty.

**Open folder.** Bookmark the root. Build Markdown-only tree. Opening a
child file is Open file inside that session. Tree stays visible.

**Switch mode.** Toggle `mode`. Same storage, same folds, same scroll
anchor as far as the line map allows. Never show both layouts.

**Toggle fold.** From gutter, keyboard, or fold-all. Update `folds`.
Relayout the current mode. The other mode picks up the same `folds` when
shown. Save does not wait on this.

**Edit in Source.** Typing updates `NSTextStorage` and undo. Debounced
reparse rebuilds the index and repairs fold IDs. Preview, when next shown,
uses the new index.

**Save.** Write the full `text` as UTF-8. Never the folded view, never
Preview HTML.

**Theme change.** Apply tokens to Preview attributed string and Source
highlighting; gutter and minimap follow.

## Requirements

### Functional

- **R1.** Preview renders GFM: CommonMark, tables, task lists,
  strikethrough, footnotes. No house dialect. Math, Mermaid, and raw HTML
  are not first-class preview features.
- **R2.** Default mode is Preview on Mac, iPhone, and iPad. The user can
  switch to Source; they cannot display both.
- **R3.** Mac: Source / Preview controls in the document title bar.
  iPhone / iPad: a slider (or equivalent) to enter Source.
- **R4.** Fold ATX heading sections and fenced code blocks in Preview and
  Source. Fold all / unfold all. Gutter chevrons. Shared fold state across
  mode switch.
- **R5.** Save, autosave, and export-to-disk write the complete unfolded
  source.
- **R6.** Mac: line-number gutter in Preview and Source (source line
  numbers) with fold chevrons in that gutter.
- **R7.** iPhone / iPad: line numbers optional; a slim fold gutter remains
  when numbers are off. Folding works in both modes either way.
- **R8.** Open a single Markdown file (tree hidden or empty) or a folder
  (tree of Markdown only, nested folders, no other files, no dotfiles).
- **R9.** Six named themes plus one custom (background color, text style
  Auto / Light / Dark). Card picker, live sample, apply on click/tap.
  Hover-preview on Mac.
- **R10.** Mac tabs. iPhone and iPad: one document; switch via tree and
  recents.
- **R11.** Mac minimap in the current mode; folded ranges hidden or
  compressed. iPad minimap not required. iPhone: no minimap.
- **R12.** Recents for files and folders; UTF-8; revert; no account; no
  telemetry; no network required for editing.
- **R13.** Outline jump, find/replace across folds, go-to-line, status bar,
  zoom, and keyboard shortcuts (including iPad hardware keyboard) as v1
  Should items — required before calling the board complete unless this
  file is revised.

### Non-functional

- **N1.** Native clients only (Swift / AppKit / UIKit / TextKit 2). Not
  Electron, not a web-view editor.
- **N2.** Parser is cmark-gfm. UI does not re-implement GFM.
- **N3.** Folding is a **layout** concern: hide via TextKit 2 fragments
  owned by Markus, not by rewriting the buffer and not by collapsing
  paragraph styles on `NSTextStorage`. Tests must prove disk output equals
  the full buffer after folds.
- **N4.** iOS folder access uses security-scoped bookmarks so recents
  still work after relaunch.
- **N5.** Verify on Mac, iPhone simulator, and iPad simulator before a
  ticket is `done`.

## Acceptance criteria

- A GFM fixture (headings, table, task list, strikethrough, footnote,
  fenced code) matches the claimed dialect in Preview.
- On Mac, iPhone, and iPad: open a long `.md`, land in Preview, fold a
  heading and a fence, fold all / unfold all, switch to Source and see the
  same folds, save, and the file on disk is complete and unfolded.
- Mac Preview and Source both show source line numbers and fold chevrons.
- iPhone/iPad can hide line numbers and still fold from the slim gutter.
- Single-file open and folder open both work; tree listing matches R8.
- Theme picker matches R9.
- Mac has tabs and a fold-aware minimap; iPhone has neither; iPad has no
  tabs and no required minimap.
- Find/replace hits text inside a folded region without requiring unfold
  first (or unfolds only as needed and still replaces in the full buffer).
- Core editing works offline with no account.

## Testing requirements

Ticket **Verify:** lines must use these commands (adjust simulator names
to what the Xcode of the day provides, but keep three destinations).

Project tests (Mac):

```bash
xcodebuild -scheme Markus -destination 'platform=macOS' test
```

Project tests (iPhone simulator):

```bash
xcodebuild -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Project tests (iPad simulator):

```bash
xcodebuild -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro (13-inch)' test
```

A ticket that only touches Mac-only chrome (tabs, minimap) still runs the
macOS test destination. A ticket that changes the shared editor, parser,
or folds must pass **all three**.

Parser/index logic should be covered by Swift tests that do not require a
simulator where practical (same `xcodebuild … test` invocation).

There is no `npm test`. Do not invent a web toolchain.

## Commit criteria

Before marking a ticket or subtask done, and before any git commit:

- [ ] Plan-task verification command passed (RED then GREEN)
- [ ] The change meets the matching requirement and acceptance criteria
- [ ] `xcodebuild` tests passed for the destinations this ticket requires
      (see Testing requirements)
- Commit message format: `{ticket-id} {task-id}: {title}`

## Tasks Breakdown

Each item becomes one ticket after this file is approved. The detailed
implementation plan is written on the ticket (`bora-plan`), not here.

1. **Multiplatform scaffold** — Xcode project / scheme `Markus`, macOS +
   iOS + iPadOS targets, SwiftUI shell, cmark-gfm linked, empty document
   window. Verify: `xcodebuild` builds all three destinations.
2. **Folding spike** — Parse a file with cmark-gfm, build the block index,
   custom TextKit 2 view hides heading and fence fold extents in Preview
   and Source, shared fold state, save writes the full buffer. This ticket
   *is* the editor-view decision; if it is janky, stop and reopen design.
3. **Document lifecycle** — Open/save/revert/autosave, UTF-8, recents for
   a single file, dirty state, security-scoped access on iOS.
4. **GFM Preview completeness** — Tables, task lists, strikethrough,
   footnotes, fenced code, themed tokens. Fixture tests for truthful
   preview.
5. **Mode chrome** — Default Preview. Mac title-bar Source / Preview.
   iPhone / iPad slider (or equivalent). Never both layouts.
6. **Gutters** — Mac line numbers + fold chevrons in both modes. iOS
   optional numbers + slim fold rail. Source line map, go-to-line ready.
7. **Folder tree** — Open folder, nested Markdown-only tree, select file,
   bookmarks persist.
8. **Theme picker** — Six named themes, custom background + Auto / Light /
   Dark, live sample, hover-preview on Mac, apply to the open document.
9. **Mac tabs and minimap** — Tabbed `NSDocument` windows. Minimap of the
   current mode that hides or compresses folds. Not on iPhone; not required
   on iPad.
10. **Editor QoL** — Outline jump, find/replace across folds, go-to-line,
    status bar, zoom, keyboard shortcuts (Mac and iPad hardware keyboard).

Do not create tickets for Skip items.

## Risks and assumptions

- **Folding in TextKit 2 is the main risk.** Stock `NSTextView` /
  `UITextView` do not invoke a custom `NSTextLayoutFragment` (confirmed on
  ticket 02). v1 owns the layout manager. Ticket 2 remains the hard gate.
- **Preview line numbers are source lines**, not visual wrapped lines.
  Wrapped Preview blocks may look sparse in the gutter; that is intended.
- **cmark-gfm footnotes** must be enabled explicitly. Fixture tests catch
  a misconfigured build.
- **iOS folder bookmarks** expire or fail if the user moves the folder;
  recents must fail cleanly, not crash.
- **`NSTextStorage` may not love multi-megabyte files.** v1 assumes
  reasonable document sizes. Rope/mmap is a later spike, not a hidden v1
  requirement.
- **Assumption:** One Xcode project, one scheme, three destinations.
- **Assumption:** MIT, no telemetry, no network for core editing.
- **Assumption:** If cmark-gfm or TextKit 2 cannot meet GFM + folding
  acceptance, reopen design (possible fallback: pulldown-cmark / Rust core).
  Do not invent a fourth stack on a ticket.

## Open questions

- Names and palettes of the six built-in themes (implementation, not
  architecture).
- Exact iOS slider control (UISlider vs custom scrubber vs segmented
  equivalent) — must stay exclusive-mode, not a split.
- Simulator device names in CI when the lab Xcode differs from
  `iPhone 16` / `iPad Pro (13-inch)`; commands above are the template.
- 2026-08-15: **A** — own `NSTextLayoutManager`; fragment exclude. Do not
  use collapsed paragraph styles as the fold mechanism.

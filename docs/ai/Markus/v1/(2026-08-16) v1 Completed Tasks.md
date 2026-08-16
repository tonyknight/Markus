---
hierarchy:
- Markus
- v1
last_reviewed: 2026-08-16
focus: "v1 board complete; remaining work is backlog, not open tickets"
---

# v1 Completed Tasks

This is a wrap-up of Markus v1 after the Requirements Tasks Breakdown
board closed. Product intent is in `(2026-08-15) v1.md`. Architecture and
acceptance are in `(2026-08-15) v1 Requirements.md`. Ticket detail lives
under `tickets/`. `Status.md` is auto-generated and was not used as a
source of edits.

Work landed on branch `bora/Markus-v1` (merge target `main`). The board
is **10 of 10 done**. Integration (local merge, PR, or keep the branch)
was not chosen at close.

Architecture that shipped: **C** — native Apple UI, custom TextKit 2
editor that owns `NSTextLayoutManager`, **cmark-gfm** parser, Swift
block index. Folds hide via zero-height `FoldingTextLayoutFragment`s,
not by rewriting the `.md` and not by collapsing paragraph styles on
`NSTextStorage`.

Verify destinations used in the lab: macOS, iPhone 17 simulator, iPad
Pro 13-inch (M5) simulator. OS floor: macOS 14 / iOS 17 / iPadOS 17.

---

## What was done

v1 is a native Markdown app for Mac, iPhone, and iPad. It opens ordinary
files (or a folder of Markdown files), lands in Preview, and can fold
ATX heading sections and fenced code in both Preview and Source. Save
always writes the full unfolded UTF-8 source. There is no account, no
telemetry, and no network requirement for editing.

### Board (all closed)

| Ticket | Title | What shipped |
|---|---|---|
| 20260815-01 | Multiplatform scaffold | Xcode project / scheme `Markus`, three destinations, SwiftUI shell, cmark-gfm linked |
| 20260815-02 | Folding spike | Parser → block index → Markus-owned TextKit 2 view; heading and fence folds; shared fold state; full-buffer save. After review, hide is layout fragments, not paragraph-style squash |
| 20260815-03 | Document lifecycle | Open / save / revert / autosave, UTF-8, recents (files and folders), dirty flag, security-scoped access on iOS (and Mac recents bookmarks) |
| 20260815-04 | GFM Preview completeness | Tables, task lists, strikethrough, footnotes, fenced code, themed tokens on the same `NSTextStorage` (no WebKit HTML preview) |
| 20260815-05 | Mode chrome | Default Preview; exclusive Source XOR Preview; Mac title-bar controls; iPhone / iPad slider (or equivalent) |
| 20260815-06 | Gutters | Mac source line numbers + fold chevrons in both modes; iOS slim fold rail; source line map |
| 20260815-07 | Folder tree | Open folder, nested Markdown-only tree (`.md` / `.markdown` / `.mdown` / `.mkd`, no dotfiles), child open, root security scope held for the session |
| 20260815-08 | Theme picker | Six named palettes (Daylight, Lampblack, Fog, Parchment, Meadow, Harbor) plus custom background + Auto / Light / Dark; card picker; Mac hover-preview with a non-modal settings pane |
| 20260815-09 | Mac tabs and minimap | `NSDocument` tabbed windows on Mac; iOS stays one session; fold-aware minimap on Mac only |
| 20260815-10 | Editor QoL | Outline from the block index, find/replace on the full buffer (including folds), go-to-line, status bar, zoom, shortcuts; chrome for Find (⌘F) and Go to Line (⌘L); jump scrolls packed Y on-screen; Preview zoom scales GFM span fonts |

### Product spine (must / should)

- **Truthful GFM preview** on the source buffer, not a second HTML document.
- **Folding** of ATX headings (through the next same-or-higher heading) and
  fenced code, in Preview and Source, on every platform, with gutter
  chevrons and fold-all / unfold-all. Disk stays unfolded.
- **One mode at a time**, default Preview.
- **File or folder** open; folder tree is Markdown-only.
- **Theming** as specified in R9.
- **Mac:** line numbers, tabs, minimap. **iPhone:** no tabs, no minimap.
  **iPad:** no tabs; minimap not required.
- **Should list (R13)** is in: outline, find/replace across folds,
  go-to-line, status, zoom, keyboard shortcuts (Mac and iPad hardware
  keyboard via SwiftUI `.keyboardShortcut` on chrome).

### Out of scope (honored)

No split view, PKM, AI, plugins, key remap, math, Mermaid, first-class
raw HTML preview, Windows/Linux, multi-cursor, project search, PDF/RTF
export, or list / quote / `#region` folding as a v1 commitment.

---

## Risks that remain

These did not block the board. They can still bite a first-user or App
Store build.

### Sandbox and recents

- Mac `startAccessing` can return `false` and still be treated as held
  (`isAccessingRoot` is set in `init`, not from the OS return).
- A failed bookmark `makeBookmark` can store a path-only recent that
  will not reopen under sandbox.
- Mac bookmark resolve falls back to non-scoped options if
  `.withSecurityScope` fails.
- Folder bookmarks live on recents, not as a first-class
  `FolderSession.bookmark` field. If the user moves a folder, recents
  should fail cleanly; that path is easy to get wrong on device.

### Document dirty / save

- Dirty publish is wired from `insertTextAtCaret` / host insert, not
  from undo or every direct `NSTextStorage` edit.
- Typing may not call `NSDocument.updateChangeCount(.changeDone)`, so
  Mac close/save chrome can disagree with the session dirty flag.

### Editor UX vs tests

- Fold current (⌘⇧K) and the status line follow **last jump**, not a
  live caret or scroll position. Clicks in the document often do not
  update that Y.
- Outline shortcut is on the Outline **menu**, so it may open the menu
  instead of the outline sheet.
- There is no SwiftUI `.commands` scene; shortcuts live on toolbar
  buttons. iPad hardware-keyboard coverage is unproven beyond that.
- Repeat ⌘1 after the tree already has focus may not re-apply focus
  (`onChange` of `isTreeFocused` does not fire if the flag stays true).
- Outline jump / go-to-line scrolling is implemented with a platform
  scroll view, but the automated scroll test uses the fallback
  `scrollOrigin` path (no attached `NSScrollView` / `UIScrollView` in
  that test).
- iOS `showLineNumbers` is API-only: R7 “optional numbers” has no
  settings toggle yet. The slim fold rail is there; hiding numbers in
  the UI is not.

### Mac chrome

- Minimap is gray compressed bars, not token-colored. Click-to-scroll
  is unhooked.
- Theme store is per window, so two Mac tabs can disagree.
- SwiftUI `MarkusApp` body is still a Settings scene; document windows
  are AppKit `NSDocument`. That is intentional after ticket 09, but it
  is easy to “fix” by adding a SwiftUI `WindowGroup` and break tabs.
- Nested `NavigationStack` in the Mac settings side pane may hoist
  Done into the window toolbar.

### Preview and scale

- Preview is **styled source** (attributed GFM on the same buffer), not
  a typeset document. Wrapped blocks look sparse in the gutter because
  numbers are **source lines** (intended).
- Setext headings are not first-class outline titles (hash-stripped
  ATX bytes).
- `NSTextStorage` is assumed fine for reasonable document sizes.
  Multi-megabyte files were an accepted v1 risk; rope/mmap is not in.

### Process / test gaps (not user-facing unless they hide bugs)

- Many plan tasks landed tests and production code in the same commit
  (no RED SHA).
- Several chrome tests assert host flags or compile-time placements,
  not the live view tree.
- Gutter chevron hit-testing is untested (API `toggleFold` is).
- Theme card `hitTest` is tested on `FoldingTextView`, not the SwiftUI
  representable host.
- iOS custom theme color persist skips sRGB convert.
- GFM fixture covers `$x$` and mermaid as non-features; there is no
  raw-HTML negative case.

---

## Items to add to the backlog

Suggested for a later project (v1.1 / v2). Do not treat this list as
open v1 tickets.

### Polish that fell out of v1 reviews

1. **iOS / iPad line-number toggle** in settings (R7 UI, not only API).
2. **Status bar and Fold current follow the live caret / scroll
   position**, not last outline/go-to-line jump.
3. **SwiftUI `commands` (or Mac main menu)** so shortcuts are not
   toolbar-only; bind Outline to present the sheet, not only the menu.
4. **Minimap:** token colors, click-to-scroll, optional iPad minimap
   (planning “Later”).
5. **Dirty sync:** every text change (including undo) publishes dirty
   and `updateChangeCount` on Mac.
6. **Tree shortcut:** re-focus the sidebar even when `isTreeFocused` is
   already true; less awkward iPhone sidebar (not a fixed-width HStack).
7. **Shared theme** across Mac tabs, or an explicit per-window choice.
8. **Security-scope honesty:** persist OS `startAccessing` result; do
   not store path-only recents when bookmarking fails; fail recents
   cleanly when a folder moved.
9. **Find bar in the editor chrome** (non-modal) if sheets feel heavy.
10. **Setext headings** in the outline, from the block index (no second
    parser).

### Planning “Later” (already listed, still true)

- Project-wide search across a folder
- Multi-cursor
- PDF / RTF export
- Syntax highlighting for many languages beyond Markdown fences
- Distraction-free / typewriter modes
- Folding lists and block quotes
- Persist-and-restore of richer window layout beyond folds and recents
- Large-document spike (rope / mmap) if `NSTextStorage` falls over

### Still skip unless product intent changes

- Side-by-side Source + Preview
- PKM, AI, plugins, user key remapping
- Math, Mermaid, raw HTML as first-class preview
- Windows / Linux
- Language-level folds inside fenced code

### Housekeeping (optional)

- Align Requirements Testing device names (`iPhone 16`, `iPad Pro
  (13-inch)`) with the lab (`iPhone 17`, `iPad Pro 13-inch (M5)`).
- Add a raw-HTML negative fixture so Preview does not accidentally
  become a browser.
- Stronger UI tests for Mac second-document tabs (window controller,
  not only “session was not replaced”).
- Decide merge vs PR for `bora/Markus-v1` onto `main`.

# Markus — project plan starting point

This document captures a planning conversation that began as a Cursor cloud agent run and is now the in-repo brief for Markus.

**Intent:** a free, open-source, native macOS Markdown editor that matches the speed and honesty of [Editorio](https://editorio.crncevic.org) and adds the one feature that editor is missing: **code folding**, so long documents stay navigable.

**Sources (public, not source code):**

- Product site: <https://editorio.crncevic.org>
- Reference manual: <https://editorio.crncevic.org/docs.html>
- Machine-readable summary: <https://editorio.crncevic.org/llms.txt>

Editorio is closed-source. This plan uses its public documentation as a capability map and engine cookbook. It does not copy Editorio’s code.

---

## 1. One-page brief

| | |
|---|---|
| **Job** | Edit long Markdown documents on a Mac without Electron, subscriptions, or a vault. |
| **Must-win** | Heading fold/unfold, fold all / unfold all, fold fenced code blocks, outline jump. |
| **Inherited from Editorio** | Native AppKit, truthful GFM preview, files stay plain `.md` on disk, no account, no telemetry. |
| **Out of v1** | PKM (wikilinks, graph), AI, plugins, Windows/Linux, 180-language code editing. |
| **License** | MIT (see `LICENSE`). |
| **Platform** | macOS 13+ (Ventura), Apple Silicon and Intel. |

Until this brief is wrong, a feature list will sprawl into an Editorio rewrite. Folding is the reason Markus exists; everything else is sequencing.

---

## 2. What Editorio actually is

Editorio is a native AppKit document editor (`NSDocument`, `NSTextView`) with a Rust document core. Marketing mentions Highlightr / highlight.js; the reference manual is more specific and more useful for planning:

```
Swift / AppKit  (windows, undo, keyboard, preview drawing)
        ↕  C ABI + Swift wrapper
Rust merkdown-core
  • memmap2     — O(1) file open
  • ropey       — editable buffer (B-tree of UTF-8 chunks)
  • pulldown-cmark — CommonMark 0.31 + GFM, pull/event parser
  • block index — byte ranges for headings, lists, code blocks, …
  • viewport    — parse/highlight only what is on screen
```

Three product principles from the manual:

1. **Truthful rendering** — Preview is GFM, not a house dialect.
2. **Sub-100 ms latency** — mmap open, viewport-scoped work, no full-document AST on the hot path.
3. **Keyboard-first** — palette, shortcuts, mouse optional.

It is not a PKM app, not Electron, and not a folding editor. Math, Mermaid, raw HTML, HTML export, key remapping, and plugins are explicitly out.

Homepage extras the manual does not fully back:

- True Vim editing (docs only mention J/K in Preview).
- “Tree-sitter-grade” highlighting (the engine is regex-lite; tree-sitter is described as a future-compatible swap).

Treat Editorio as the speed/honesty bar, not the feature ceiling.

---

## 3. Capability map

Use this as the backlog skeleton. Tags: **Must** for Markus v1, **Should** for Editorio-parity after folding works, **Later** / **Skip**.

| Area | What Editorio ships | Markus tag | Folding implication |
|---|---|---|---|
| Open / save | `NSDocument`, mmap, security-scoped recents | Must | Folds are view state; the file on disk stays unfolded |
| Buffer | `ropey` rope, dirty vs mmap baseline | Must (once the view is chosen) | Fold ranges must be byte offsets that survive edits |
| Markdown | pulldown-cmark + GFM (tables, tasks, footnotes, strike, heading attrs) | Must | Heading + fenced-code folds fall out of the block index |
| Source | writable `NSTextView`, gutter, indent, comments, brackets | Must | This is where folding has to live |
| Preview | read-only attributed preview from parsed blocks; skip preview above 250 MB | Must | Folding is a Source-mode problem first |
| Outline | ⌘⇧O from the block index | Must | Outline and fold ranges share one index |
| Nav | tabs, sidebar, ⌘P / ⌘⇧P, ⌃G | Should | After the spike |
| Find | find/replace, project search | Should (find); Later (project search) | Find must work across folds |
| Minimap | always-on, theme-colored | Later | Must hide or compress folded regions or it will lie |
| Multi-cursor | Sublime-style ⌘D / ⌥-click | Later | Multi-cursor + folds is a hazard |
| Chrome | 4 themes, zoom, distraction-free, status bar | Should | Theme must color fold markers |
| Export | PDF from preview, copy as RTF | Later | Unfolded content |
| Languages | 180+ via regex-lite | Later | Regex-lite is enough for Markdown source and fences in v1 |
| Explicitly absent | folding, key remap, math, Mermaid, plugins | Folding = Must; rest = Skip for v1 | Folding is the differentiator |

Editorio shortcut tables in the [reference manual](https://editorio.crncevic.org/docs.html) are a ready-made keyboard backlog. Copy them unless there is a reason not to — people coming from that app should feel at home.

---

## 4. Why folding is the first architectural decision

In Markdown, “code folding” almost always means:

1. **Fold a heading** — hide everything until the next heading of the same or higher level.
2. **Fold a fenced code block** — keep the opening fence (and maybe a one-line placeholder), hide the body.
3. Later: fold lists, block quotes, HTML comments / region markers, and (if Markus also edits source files) language-level folds.

Editorio already computes this structure. On open it walks top-level pulldown-cmark events into:

```text
BlockEntry { byte_start, byte_end, kind }
```

where `kind` includes `Heading(u8)` and `CodeBlock`.

Folding a heading is then: binary-search the index, find the end of the section, hide that byte range in the view. **v1 Markdown folding does not need tree-sitter.**

The hard part is the **view**. Stock `NSTextView` is a poor folding surface (layout, caret, undo, find, minimap, and line numbers all assume a contiguous document). Apple showed collapsible TextKit 2 sections at WWDC 2026, aimed at the **2027** OS releases — too late if Markus should ship on macOS 13/14/15/26.

So the plan must choose a text view **now**, with folding as a requirement, not a v2 patch.

---

## 5. Architecture to copy (the idea, not the binary)

Keep Editorio’s split. It is the right one for both speed and folding:

| Layer | Job | Suggested building blocks |
|---|---|---|
| App shell | `NSDocument`, tabs, menus, palette | Swift + AppKit |
| Document core | mmap, rope, GFM parse, **block index**, fold-range API | Rust crate (`ropey` + `pulldown-cmark` + `memmap2`) behind a small C ABI |
| Source view | layout, caret, **hide folded ranges**, gutter chevrons | Do **not** start from vanilla `NSTextView`. Study [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) (folding ribbon + placeholders) and [STTextView](https://github.com/krzyzanowskim/STTextView) (TextKit 2 editor view). |
| Preview | block events → `NSAttributedString` | Same parser, same index, read-only `NSTextView` |

The core should answer three questions from one index:

1. Preview: blocks intersecting this byte range
2. Outline: all headings
3. Folding: foldable ranges (heading sections + fences)

If those three APIs exist, the rest of the app is chrome.

### What not to do

- **Do not fork Editorio.** Closed-source. Use the public manual as a spec.
- **Do not start in Electron / Tauri / CodeMirror.** Folding is easy there, but VS Code and Obsidian already exist. The reason Editorio feels “perfect otherwise” is native launch, RAM, and honesty.
- **Do not fork CotEditor or MacDown as the product.** CotEditor 7 can collapse outline-inspector rows; it is still not an inline folding Markdown editor. MacDown is a preview-centric Cocoa app of another era.
- **Do not wait for Apple’s 2027 collapsible `NSTextView` APIs** as the v1 plan. Optionally design so a swap is possible later.
- **Do not build 180-language highlighting before folding works.**

Existing native Markdown apps to **read**, not necessarily fork:

- [Edmund](https://github.com/I7T5/Edmund) — AppKit + TextKit 2, file-based, live preview
- [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) — live-styled TextKit 2

Neither is folding-first; both are useful UI references.

---

## 6. Phased plan

### Phase 0 — Brief (this document)

Done enough to start. Revisit only if the job or the must-win list changes.

### Phase 1 — Spike (the real start)

One window, no document model, no Mac App Store:

1. Load a 3,000-line Markdown file.
2. Build a heading/code-block index with pulldown-cmark.
3. Fold/unfold H2 sections from the gutter and from the keyboard.
4. Caret, undo, and Find still work across a fold.
5. Save writes the **full** source, never the folded view.

**Pass/fail:** if this is janky, change the text view. Do not add Preview, tabs, or themes until it is solid. This spike *is* the architecture decision.

### Phase 2 — Document app

`NSDocument`, open/save/revert, undo coalescing, tabs, autosave, UTF-8. Rope + mmap can come in once the view is chosen.

### Phase 3 — Preview + outline

Viewport-scoped GFM preview (Editorio’s pattern: parse visible blocks, not the whole file). Outline palette (⌘⇧O) driven by the same index as folds.

### Phase 4 — Keyboard shell

Command palette, find, go-to-line, sidebar folder, status bar. Prefer Editorio’s shortcut table.

### Phase 5 — Editorio-parity (only after 1–4)

Themes, zoom, distraction-free, PDF export, fenced-block highlighting, then other languages. Minimap last: it must hide or compress folded regions.

### Phase 6 — Folding beyond v1

Nested heading fold-all, persist fold state per file (sidecar or xattr — not in the Markdown), language-level folds if Markus also becomes a code editor, fold-aware minimap.

---

## 7. Suggested v1 fold commands

Steal muscle memory from VS Code / Sublime; Editorio has no folds to copy.

| Action | Typical binding |
|---|---|
| Toggle fold at caret | ⌥⌘[ |
| Fold all headings | ⌥⌘0 or a palette command |
| Unfold all | ⌥⌘J |
| Fold all fenced blocks | palette |
| Toggle fold at gutter chevron | click |

Persist folds **per file in app state**, never by rewriting the document.

---

## 8. How to use Editorio’s manual while building

Treat <https://editorio.crncevic.org/docs.html> as:

- a **feature inventory** (shortcut and GFM tables are a ready-made backlog),
- an **engine cookbook** (mmap → rope → async block index → viewport query is the open pipeline to imitate),
- a **performance budget** (`<100 ms` open, 60 fps scroll, preview skipped on huge files).

Do **not** treat it as a build order. Editorio shipped folding-free because folding fights `NSTextView`. Markus’s build order is the opposite: **index → folds → document app → preview → chrome.**

---

## 9. Next local steps

Continue this work in the local clone of `tonyknight/Markus`, not in the cloud agent:

1. Pull this branch (or merge it to `main`).
2. Open the repo in Cursor Desktop.
3. Spike Phase 1: one window, one long `.md` file, heading folds that survive undo/find/save.
4. Break Phase 1 into GitHub issues only after the text-view choice is made (CodeEditSourceEditor vs STTextView vs custom TextKit 2).

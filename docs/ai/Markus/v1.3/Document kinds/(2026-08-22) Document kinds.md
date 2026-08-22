---
hierarchy:
- Markus
- v1.3
- Document kinds
last_reviewed: 2026-08-22
focus: "Open JSON, HTML, and a short language list with Markus folding — not a CotEditor clone"
routing: true
routing_cache:
  cursor:
    premium: cursor-grok-4.6-high
    standard: grok 4.6
    economy: gemini-3.7-flash
---

# Markus v1.3 — Document kinds

v1.2 made Settings a real Preferences window. Markus is still a Markdown app: `MarkdownDocument` forces every file through `net.daringfireball.markdown`, Preview substitutes GFM, and folds exist only for headings and fenced code. Opening a `.json` file today is a lie — the buffer is treated as Markdown.

v1.3 is the **document-kind** release. It lets Markus open a small, folding-first subset of programming and data files as themselves: detect type from UTI/extension, let the user override the type on a new or existing file (the CotEditor idea, implemented in our NSDocument + `FoldStore` structure), and fold the structures those languages actually have. Syntax coloring of interiors is in scope only as far as it makes those folds readable — not a marketplace of grammars.

This briefing is the basis for `(2026-08-22) Document kinds Requirements.md`. Architecture is written there for approval. Do not create tickets until the human approves that Requirements file.

CotEditor ([coteditor/CotEditor](https://github.com/coteditor/CotEditor), Apache 2.0) is a **reference for product behavior** (type assignment, outline, diagnostics), not a source tree to copy. Markus stays MIT, TextKit 2, and our fold model.

## Background

Markus exists because a honest native Markdown editor still lacked **heading and fence folding** on Mac and iOS. That is still the center. The gap now is that the same folding engine is trapped inside Markdown: JSON objects, HTML elements, and Swift functions cannot fold because the app does not admit those documents exist.

Folding is the selection criterion for which types we take. CotEditor supports dozens of syntaxes as a general text editor. We will not. We take types whose structure maps onto the fold units we already ship (a named range with a `FoldID`, a byte extent, persistence, and TextKit 2 collapse).

v1 / v1.1 / v1.2 architecture **C** stays: SwiftUI chrome, Markus-owned TextKit 2, one app-scoped `ThemeStore`. Markdown Preview substitution stays Markdown-only. Other kinds use Source-shaped editing (1:1 buffer) with folding and, where cheap, token colors. cmark-gfm remains the Markdown parser. New kinds get their own profile, not a fake Markdown parse.

## What's in, at a glance

| Area | v1.2 | v1.3 |
|---|---|---|
| Open | Every URL forced to Markdown | UTI/extension → `DocumentKind`; user can reassign |
| New file | Always Markdown | User picks a kind (default Markdown) |
| Fold units | Heading, fenced code | Kind-specific nodes (object, element, function, …) on the same `FoldStore` |
| Preview mode | GFM substitution | Markdown: GFM substitution. HTML/SVG: rendered WebView (separate path). JSON/TOML: Source + folds only |
| Color | Markdown roles (`ThemeTokens`) | Markdown roles plus a small inner code palette on non-Markdown (and later on fence interiors) |
| Inspector | Out of scope (v1.4) | Outline data must exist so v1.4 can show it; no new sidebar chrome here |

## Language waves (folding impact)

Ranked by how well Markus’s existing fold model pays off. Waves are a proposed order, not a promise to ship all of them in one Requirements file.

### Wave A — tree documents (do these first)

These are documents people open *in order to collapse structure*. One honest JSON viewer with object/array folds is more valuable than eight half-highlighted languages.

| Kind | Extensions (indicative) | Fold unit | Why it belongs |
|---|---|---|---|
| JSON | `.json` | Object `{…}`, array `[…]` | Highest-impact single-file viewer. Parse errors are free diagnostics for v1.4. |
| HTML | `.html`, `.htm` | Element from start tag to matching end tag | Nested structure matches heading folds. |
| SVG | `.svg` | Same as HTML (XML elements) | Same engine as HTML. Designers open these as text. |
| TOML | `.toml` | Table / array-of-tables | Config files; sections fold like headings. |

### Wave B — brace languages (after the kernel works)

Same `FoldStore`, fold unit is a matched brace/indent block (function, type, rule). Coloring matters more here so a folded function still reads as a function.

| Kind | Extensions (indicative) | Fold unit |
|---|---|---|
| CSS | `.css` | Rule / `@media` / `@supports` block |
| JavaScript | `.js`, `.mjs`, `.cjs` | Function, class, object, block |
| TypeScript | `.ts`, `.tsx` | Same as JS plus interface/type |
| Swift | `.swift` | Type, function, closure, computed block |
| PHP | `.php` | Function, class, block (HTML islands are a later injection problem) |

### Wave C — weaker fold payoff (keep last or cut)

| Kind | Why it is last |
|---|---|
| Shell (`.sh`, `.bash`, `.zsh`) | Little reliable block structure. Heredocs and `if/fi` are messy. Worth a kind + coloring; folding may be indent- or keyword-based and must not pretend to be JSON-quality. |

**Not in the list (explicit):** Python, Ruby, Rust, C/C++, Java, Kotlin, Go, SQL, YAML-as-a-first-class-kind (YAML folding is ambiguous). Markdown stays the default kind. XML besides SVG is not a separate kind unless Requirements adds it as an HTML/SVG shared XML engine.

## Goals

- Admit a `DocumentKind` besides Markdown, detected from UTI/extension and overridable by the user for the current document and for **New**.
- Generalize folding so `FoldStore` / `FoldID` / TextKit 2 collapse work for kind-specific ranges, with the same persistence and repair story as headings/fences.
- Ship **Wave A** as the v1.3 bar unless design cuts a type. Wave B may land in the same release only if the kernel is stable; otherwise it is the next briefing.
- Keep Markdown Preview, GFM, and existing Markdown folds correct. Opening `.md` must not regress.
- Color non-Markdown buffers enough that folded headers (key name, tag name, `func foo`) are distinguishable. Full tree-sitter injection inside Markdown fences may share this coloring later; it is not the v1.3 headline.
- **HTML and SVG offer a rendered WebView preview** in addition to Source + folds. This is not Markdown substitution and not a JSON feature.
- Register the new UTIs in Info.plist so Finder/Open can hand Markus a `.json` file.
- iOS/iPadOS must **build** and open these files; chrome can stay simple (no CotEditor-scale inspector — that is v1.4).

## Non-goals

- Copying CotEditor source, syntax YAML, `SyntaxController`, or tree-sitter wiring. Reimplement inside Markus. Attribute CotEditor in prose if we cite behavior.
- CotEditor’s full syntax catalog, syntax editor UI, or user-authored `.cotsyntax` files.
- Becoming a general IDE: debug, build, git, LSP, plugins, terminals.
- Third-party linters (ESLint, SwiftLint). Parse diagnostics belong with v1.4 Inspector.
- Rendered HTML/SVG **web preview** is **in** for HTML and SVG (decided 2026-08-22): WKWebView (or equivalent) of the current buffer, not Markdown substitution, not for JSON/TOML. Script execution, network, and file URL policy are Requirements work (default: lock down).
- Side-by-side Source and Preview for any kind.
- Language-server protocol, Tree-sitter as a mandatory kernel (it is one option for Wave B, not a given).
- Windows/Linux.
- Changing the v1.2 theme families. Inner code colors should derive from or sit beside `ThemeTokens`, not replace Appearance.

## Target users

Tony and other people who already use Markus for Markdown and currently bounce to another editor for a single JSON/HTML/CSS file. They want one native app, folding that matches the document, and no Electron. They do not need Visual Studio Code’s language pack.

## User stories

- As a developer, I want to open `package.json` in Markus, fold objects and arrays, and edit a key, so I do not switch apps for a one-file change.
- As a developer, I want **File → New** to ask (or remember) JSON vs Markdown, so a new buffer is not a Markdown document in disguise.
- As a developer, I opened a `.html` file as Markdown by mistake; I want to set the document kind to HTML and get element folds.
- As a designer, I want to flip HTML or SVG to a rendered preview so I can check layout without leaving Markus, then return to Source to fold and edit.

## Constraints

- Files on disk stay plain UTF-8 (or a documented encoding path if we must; do not silently recode).
- One window/document architecture: do not spawn a second NSDocument class hierarchy unless design proves `MarkdownDocument` cannot grow a kind field.
- Sandbox, bookmarks, recents, and folder library stay.
- Verify with `xcodebuild` Debug **build** on macOS plus iPhone and iPad simulators when shared code changes (same gate as v1.2).
- Performance: folding and coloring must not lock typing on a multi-megabyte JSON file. Incremental or bounded work, same spirit as v1.1 span-styling budgets.

## Success criteria

- A `.json` file opened from Finder folds objects/arrays and round-trips edits to disk as JSON text.
- New file can be created as JSON (and Markdown). Kind is visible and changeable.
- Markdown documents are indistinguishable from v1.2 in Preview, folds, and Settings.
- Wave A kinds listed in the approved Requirements each have at least: open, save, kind detection, folds, outline items available to v1.4.
- No CotEditor code in the tree.

## Architecture

Locked in Requirements as **A**: one NSDocument, pluggable `SyntaxProfile`, dedicated JSON parser, shared XML path for HTML+SVG, locked WKWebView for HTML/SVG Preview only. Wave B parser (brace matcher vs tree-sitter) is chosen on that ticket if the Wave A kernel is stable.

## Relationship to v1.4

v1.3 produces outline items and parse diagnostics as **data**. v1.4 Inspector is the chrome (document info, outline pane, warning list). Do not build the CotEditor-style right sidebar in this project.

## Open questions

- ~~Does HTML/SVG get a rendered WebView preview, or only Source + folds?~~ **Decided 2026-08-22:** HTML/SVG get a rendered WebView preview in addition to Source + folds. JSON/TOML do not. Markdown Preview stays GFM substitution.
- ~~Does Wave B ship in v1.3 or wait until the JSON/HTML kernel is proven?~~ **Decided 2026-08-22:** Wave B (CSS, JS, TS, Swift, PHP; Shell last) ships in **v1.3 if the Wave A kernel is stable**. If JSON/HTML/SVG/TOML folding + kind assignment is not solid, Wave B slips to a follow-on briefing rather than stretching a broken kernel.
- ~~Is kind override persisted per file (bookmark/sidecar) or session-only?~~ **Decided 2026-08-22:** Extension/UTI chooses the kind by default. An override is persisted per file **only when the user explicitly pins** a kind. Unpinning returns to extension/UTI.
- ~~Default for untitled documents: always Markdown, or last-used kind?~~ **Decided 2026-08-22:** Untitled / File → New is always Markdown. Creating a JSON (or other) file is an explicit New of that kind, not a remembered last type.

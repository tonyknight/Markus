---
hierarchy:
- Markus
- v1.3
- Document kinds
last_reviewed: 2026-08-24
focus: "DocumentKind kernel; Wave A folding; HTML/SVG WebView; Wave B if kernel is solid; verify by build"
---

# v1.3 Document kinds Requirements

Product intent lives in `(2026-08-22) Document kinds.md`. This file is the architecture, the requirements, and the Tasks Breakdown that becomes tickets. Implementation plans are written **on each ticket**, not here.

Architecture: **C spine unchanged, document model extended.** SwiftUI chrome, Markus-owned TextKit 2, one app-scoped `ThemeStore`, one NSDocument class. Markdown keeps cmark-gfm and Preview substitution. Other kinds attach a `SyntaxProfile` that feeds the same `FoldStore` / `FoldingTextView`. CotEditor is a behavior reference only — no CotEditor source in the tree.

## Overview

v1.3 is a **document-kind** release. Markus stops treating every file as Markdown. It detects JSON, HTML, SVG, TOML (Wave A) from UTI/extension, folds their real structure, and lets the user pin a kind when the extension is wrong. HTML and SVG also get a full WKWebView Preview (script on, local folder, http(s) assets). Wave B (CSS, JS, TS, Swift, PHP; Shell last) ships in this release **only if** Wave A’s kernel is solid; otherwise those tickets slip rather than stretching a broken kernel.

v1.4 Inspector is **not** this board. Profiles must still emit outline rows and parse diagnostics as data so that board can consume them.

Quality of this release is judged by **running the app** (open a `.json`, fold, save; flip HTML to Preview). Automated tests are not the gate. Parser/fold tests may be added if they can fail; they are not required to close a ticket.

## Goals

- `DocumentKind` besides Markdown, from UTI/extension, with an explicit pin to override.
- File → New is one command. A centered type picker defaults to Markdown; the user can choose any shipped kind. Per-kind New menu items are not used.
- Same `FoldStore` / TextKit 2 collapse for kind-specific ranges; persistence and repair as today.
- Wave A: JSON, HTML, SVG, TOML — open, save, detect, fold, outline data, diagnostics data.
- HTML/SVG: Source + folds **and** a rendered WebView Preview (not Markdown substitution).
- JSON/TOML and Wave B: Source + folds only.
- Markdown Preview, GFM, heading/fence folds, Settings: no regression.
- Enough inner coloring that a folded header is readable (key, tag, `func`).
- Info.plist registers the new types. iOS/iPadOS **build** and can open them.

## Non-goals

- CotEditor source, `.cotsyntax`, `SyntaxController`, or vendored CotEditor packages.
- CotEditor’s full language catalog, syntax-definition editor, user-authored grammars.
- IDE features: debug, build, git, LSP, plugins, terminal.
- Third-party linters (ESLint, SwiftLint, PHPStan). Parse diagnostics are data for v1.4, not a warnings UI here.
- v1.4 inspector chrome (document info pane, outline sidebar, warning list).
- Side-by-side Source and Preview.
- JSON/TOML WebView or “pretty tree” view besides folding the text.
- Language-server protocol. Tree-sitter is optional for Wave B, not the Wave A kernel.
- Python, Ruby, Rust, C/C++, Java, Kotlin, Go, SQL, YAML-as-a-kind. XML besides SVG is not a separate kind (HTML+SVG share one XML engine).
- Changing v1.2 Appearance families or adding code-token wells. Inner colors derive from existing `ThemeTokens`.
- Fence-interior language injection in Markdown (may reuse the color map later; not a v1.3 headline).
- Windows/Linux.
- Expanding MarkusTests as a substitute for looking at the window. No TDD requirement on this board.

## Architecture

### Decisions (from the briefing)

| Question | Decision |
|---|---|
| Document classes | **One** NSDocument (`MarkdownDocument` may keep its type name). Kind is a field, not a subclass per language. |
| Profiles | Pluggable `SyntaxProfile` per `DocumentKind`. Markdown profile = today’s cmark path. |
| Wave A | JSON, HTML, SVG, TOML. **Release bar.** |
| Wave B | CSS, JS/TS, Swift, PHP; Shell last. **In v1.3 if Wave A kernel is stable**; otherwise slip those tickets. |
| HTML/SVG Preview | Full WKWebView render of the current buffer (`loadFileURL` + live buffer). Not `PreviewSubstitution`. Not for JSON/TOML. |
| WebView policy | No script execution, no network. Load from the buffer string, not an unconstrained `file://` sandbox escape. |
| Kind detection | Extension/UTI by default. |
| Kind pin | Persist per file **only** when the user explicitly pins. Unpin → follow extension/UTI again. |
| File → New | One **New** (⌘N) plus a centered type picker, default Markdown. Not one menu item per kind. Launch untitled (no picker) stays Markdown. |
| Parser — JSON | Dedicated JSON parser (Foundation or equivalent). Not tree-sitter. |
| Parser — HTML/SVG | Shared XML/HTML tokenizer; SVG is not a second engine. |
| Parser — Wave B | Brace/block matcher or tree-sitter — chosen on the Wave B ticket if the kernel is ready. PHP does **not** fold HTML islands in this release. |
| Shell | Kind + coloring; folds are best-effort and must not claim JSON quality. |
| Inspector | Data only (outline items, diagnostics). No new sidebar. |
| Source vs Preview | Markdown: unchanged GFM substitution. JSON/TOML/Wave B: Source only (Preview hidden). HTML/SVG: Source = 1:1 buffer + folds; Preview = WebView. |
| Default mode | Markdown honors Editor default (v1.2). HTML/SVG open in **Source**. JSON/TOML/Wave B open in Source. |
| Coloring | Small inner roles (keyword, string, comment, number) derived from `ThemeTokens` (body/fence/link). No new Appearance wells. |
| CotEditor | Cite in comments/docs if we match behavior. Do not copy files. |

### Stack

| Layer | Choice | Change from v1.2 |
|---|---|---|
| NSDocument | Same class; `DocumentKind` on the session | **Changed** — was forced Markdown |
| Detection | UTI/extension map; optional pin in app storage keyed by file identity | **New** |
| Syntax | `SyntaxProfile` protocol: foldables, outline rows, diagnostics, highlight spans | **New** |
| Markdown | cmark-gfm, substitution, heading/fence folds | Unchanged behavior |
| JSON | Dedicated parser → object/array fold extents | **New** |
| HTML/SVG | Shared XML/HTML tokenizer → element folds; WKWebView Preview | **New** |
| TOML | Table / array-of-tables folds | **New** |
| Folding | `FoldStore` + TextKit 2; `FoldID` kind is profile-defined, not only heading/fence | **Extended** |
| Preview | Markdown substitution **or** HTML/SVG WebView **or** hidden | **Gated on kind** |
| Theme | `ThemeStore` unchanged; derived code colors | **Extended use** |
| Persistence | Folds as today; kind pin only when explicit | **New pin key** |
| Info.plist | Additional imported/exported types + document types, same `NSDocumentClass` | **Changed** |

Minimum OS unchanged: macOS 14, iOS 17, iPadOS 17.

### Components

1. **`DocumentKind`.** Closed set for this release: `markdown`, `json`, `html`, `svg`, `toml`, and Wave B cases `css`, `javascript`, `typescript`, `swift`, `php`, `shell` if those tickets ship. Each kind has display name, extensions, UTIs.

2. **Detection and pin.** `MarkusDocumentController.typeForContents` and Open/New stop hard-coding Markdown. Map URL → kind via extension/UTI. If a pin exists for that file identity, use the pinned kind. Untitled with no URL is Markdown. Saving an untitled JSON (created via New JSON) writes `.json` (or the kind’s default extension) unless the user picked another.

3. **`SyntaxProfile`.** Given the buffer string, returns: foldable blocks (`FoldID` + byte/line extent + anchor), outline rows (`OutlineItem` generalized: title, sourceLine, level), diagnostics (`line`, `message`, `severity`), and optional highlight spans for the inner color roles. Markdown profile wraps existing `BlockIndex` / parser. Switching kind rebuilds folds via `FoldStore.repair`.

4. **Fold identity.** `FoldID.Kind` is no longer only heading/fence. Persist and repair still use kind + anchor + startLine. Old Markdown fold records must still load.

5. **Kind assignment UI (Mac).** Format (or File) menu: **Document Kind** list, **Pin Kind** / **Unpin Kind**. No inspector pane. iOS: a compact control (toolbar or existing sheet) that can set and pin kind; not a new Settings window.

6. **New document commands.** File → New (⌘N) is one command. A centered type picker defaults to Markdown and can create any shipped kind. Launch untitled with no picker stays Markdown. iOS new untitled stays Markdown unless the user picked another kind.

7. **JSON profile.** Parse objects and arrays. Fold from after the opening `{`/`[` through the matching closer (opener line stays visible, same idea as fence folds). Invalid JSON: no crash, empty or partial folds, at least one diagnostic. Save writes the buffer as UTF-8 text (we do not pretty-print unless the user typed it).

8. **HTML + SVG profile.** One tokenizer. Fold elements with a matching end tag (and paired SVG). Void/self-closing tags are not foldable. Outline: tag name (+ id/class if cheap). Preview: WKWebView full render of the current buffer (script on, sibling files via `loadFileURL`/`allowingReadAccessTo`, http(s) subresources). In-page navigation stays in that WebView — no URL bar.

9. **TOML profile.** Fold tables and array-of-tables. Outline: table headers.

10. **HTML/SVG mode chrome.** Existing Preview/Source control. Source = `FoldingTextView` 1:1. Preview = WebView replacing the text view **without** tearing down the document session (do not repeat the v1.1 Settings unmount bug). Switching back to Source restores caret/folds.

11. **Inner coloring.** Apply derived keyword/string/comment/number (and a default body) on non-Markdown Source. Markdown Source stays v1.2 (body color, 1:1). Do not recolor Markdown Preview via this map.

12. **Wave B (conditional).** Shared brace/block fold helper. CSS: rule and at-rule blocks. JS: function/class/object/block. TS: same + `.tsx` as TypeScript kind (JSX tags are not a separate fold unit). Swift: type/func/closure. PHP: function/class/block only — no HTML-island folds. Shell: kind + color; optional keyword/indent folds; must degrade safely.

13. **v1.4 hooks.** `DocumentHost` (or session) exposes `outlineItems` and `diagnostics` from the active profile. Markdown headings still flow through the existing outline jump. No new sidebar UI.

### Data model

```text
DocumentKind    markdown | json | html | svg | toml
                | css | javascript | typescript | swift | php | shell   // Wave B, if shipped

SyntaxProfile   foldables, outlineRows, diagnostics, highlightSpans

FoldID          kind (profile string), startLine, anchor
Block           id, lines, bytes, foldExtent                 // generalized; Markdown heading/fence remain

KindPin         optional per-file: DocumentKind              // only if user pinned
Detection       pin ?? map(extension/UTI) ?? markdown

Editor surfaces
  markdown:  Source = 1:1 buffer; Preview = GFM substitution
  html/svg:  Source = 1:1 + folds + color; Preview = full WKWebView render
  json/toml/Wave B: Source only

CodeColorRoles  keyword, string, comment, number             // derived from ThemeTokens
```

Disk files remain plain text. Kind pin and folds stay in app storage, not in the file.

### Key flows

**Open `package.json` from Finder.** UTI/extension → json. JSON profile builds object/array folds. Buffer is the file bytes as UTF-8. Preview control hidden. Save writes the buffer.

**Open `notes.md`.** Markdown as today. Preview substitution, heading/fence folds, Settings unchanged.

**Open `page.html`.** HTML profile, element folds, Source first. Preview is a full WebKit render of the current buffer (CSS, JS, images, fonts, relative and http(s) assets). Edits in Source; Preview refreshes on commit of the buffer (debounce is an implementation detail; must not lose the session).

**File → New.** Markdown untitled. File → New JSON: untitled, kind json, Source, no pin until saved+pinned.

**Wrong kind.** A `.txt` file of JSON: user sets Document Kind → JSON and **Pin Kind**. Next open uses JSON. Unpin: `.txt` maps to Markdown (or whatever UTI says).

**Wave B slip.** If after JSON+HTML+SVG+TOML the kernel is not solid (detection, folds, Markdown regression), remaining Wave B tickets are left todo / moved — do not ship half-working Swift folds on a broken kind switch.

## Requirements

- **R1.** Opening a file chooses `DocumentKind` from extension/UTI. Markus no longer forces every URL to Markdown.
- **R2.** The user can set the current document’s kind from the UI. **Pin Kind** persists that choice for the file; **Unpin** returns to extension/UTI. Untitled files have no pin.
- **R3.** File → New (⌘N) creates Markdown. There are explicit New commands for each shipped non-Markdown kind.
- **R4.** Markdown documents keep v1.2 Preview substitution, GFM, heading and fence folds, and Settings behavior.
- **R5.** JSON: objects and arrays fold; invalid JSON does not crash; the buffer round-trips to disk as UTF-8 text.
- **R6.** HTML and SVG share one XML/HTML folding engine; elements with matching end tags fold; Source is 1:1 with folds.
- **R7.** HTML and SVG Preview is a full WebKit render of the current buffer (script on, local folder, http(s) subresources). Switching Source/Preview does not unmount the document session or lose folds. Not a URL-bar browser.
- **R8.** TOML tables (and array-of-tables) fold.
- **R9.** Each shipped kind exposes outline rows and parse diagnostics on the session for v1.4. Markdown headings remain outline-jumpable.
- **R10.** Non-Markdown Source uses derived inner colors (keyword, string, comment, number) so folded headers read as structure. Markdown Source stays 1:1 body styling.
- **R11.** Info.plist advertises the shipped kinds so Finder/Open and the file importer can hand Markus those files.
- **R12.** iOS and iPadOS **build** and can open shipped kinds. Inspector chrome is not required. Kind assignment exists in some compact form.
- **R13.** Wave B kinds (CSS, JavaScript, TypeScript, Swift, PHP; Shell last) ship in this release only if the Wave A kernel (R1–R8) is stable. PHP does not fold HTML islands. Shell folds are best-effort.

### Non-functional

- **N1.** No CotEditor source, syntax YAML, or packages in the Markus tree.
- **N2.** Folding and coloring must not freeze typing on a large JSON file (multi‑MB). Work is incremental or bounded; same spirit as v1.1 span budgets.
- **N3.** Shared-layer edits compile for macOS, iOS, and iPadOS.
- **N4.** No new unit-test suite work is required to close a ticket. Do not add tests that cannot fail, and do not block on `xcodebuild test`.
- **N5.** **Product override (2026-08-24):** HTML/SVG Preview is a full render of the user’s own page, not an untrusted sandbox. Script, sibling files, and http(s) subresources are in. Do not re-lock Preview. Not a URL-bar browser (`target=_blank` stays in the same WebView).
- **N6.** Files on disk stay the user’s bytes (UTF-8 text). No silent pretty-print or recode on save.

## Acceptance criteria

- [ ] A `.json` file opened from the app folds objects/arrays; edits save as the buffer text; Preview is not offered.
- [ ] A `.md` file is indistinguishable from v1.2 in Preview, heading/fence folds, and Settings.
- [ ] File → New is Markdown; File → New JSON creates a JSON untitled.
- [ ] Pinning HTML on a mislabeled file survives relaunch; unpinning follows the extension again.
- [ ] An `.html` / `.svg` file folds elements in Source and shows a full WebView render in Preview; the editor session stays mounted.
- [ ] A `.toml` file folds tables.
- [ ] Outline items and at least one diagnostic on broken JSON are available on the session (even if nothing displays them yet).
- [ ] Finder/Open (or the in-app importer) accepts the shipped extensions.
- [ ] macOS Debug **build** succeeds after each task; iOS/iPad **build** succeeds when shared code changed.
- [ ] Wave B is either working for the listed kinds or explicitly slipped — not half-wired.

## Testing requirements

This board **verifies by building**, then by opening files in the app. After **every** plan task, from `Markus/`:

```text
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -configuration Debug build
```

If the task touched shared editor/parser/profile/WebView/Info.plist types compiled into the iOS target, also:

```text
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```

Ticket **Verify:** lines copy these build commands. Do not invent `xcodebuild test` or TDD RED/GREEN as the bar.

After a kind/fold/WebView task, the implementer (or human) **runs the app** and opens a fixture of that kind. That inspection is part of done.

## Commit criteria

Before marking a ticket or subtask done, and before any git commit:

- [ ] The task’s `xcodebuild` **build** command(s) succeeded
- [ ] The change meets the matching requirement and acceptance criteria
- [ ] For kind/fold/WebView work: a real file of that kind was opened and checked by eye
- Commit message format: `{ticket-id} {task-id}: {title}`

Do not require the unit-test suite to pass as a ticket gate. Do not write a failing test first.

## Tasks Breakdown

Each item becomes one ticket after this file is approved. The implementation plan is written on the ticket (`bora-plan`), not here.

1. **DocumentKind kernel** — enum, UTI/extension map, stop forcing Markdown in `MarkusDocumentController` / Open / importer; Info.plist types for Wave A; session carries kind. (R1, R11, R12)
2. **SyntaxProfile and fold generalization** — protocol; `FoldID` beyond heading/fence; Markdown profile wraps today’s index; `repair` still loads old Markdown folds; outline/diagnostics fields on the session. (R4, R9)
3. **Kind assignment and New** — Document Kind menu, Pin/Unpin persistence, File → New stays Markdown, explicit New JSON/HTML/SVG/TOML (Wave B New items when those kinds ship). Compact iOS control. (R2, R3, R12)
4. **JSON profile** — parser, object/array folds, outline rows, diagnostics on invalid input, Source-only, UTF-8 save. (R5, R9, N2, N6)
5. **HTML and SVG** — shared XML/HTML folds, outline, diagnostics; Source 1:1; full WKWebView Preview; session stays mounted. (R6, R7, N5)
6. **TOML profile** — table / array-of-tables folds, outline, diagnostics. (R8, R9)
7. **Derived inner coloring** — keyword/string/comment/number from `ThemeTokens` on non-Markdown Source. Markdown Source unchanged. (R10)
8. **Wave B brace languages** — CSS, JavaScript, TypeScript, Swift folds + New items + UTIs. Slip the whole ticket if Wave A is not solid. (R13)
9. **Wave B PHP and Shell** — PHP function/class/block only; Shell kind + color, best-effort folds. Slip with ticket 8 if needed. (R13)

Do not create tickets for v1.4 inspector chrome, LSP, or CotEditor imports.

**Execute note:** After ticket 6 (Wave A complete), judge kernel stability before starting tickets 8–9. If detection, Markdown regression, or JSON/HTML folds are wrong, leave 8–9 todo and treat Wave A as the releasable v1.3.

## Risks and assumptions

- **WKWebView + sandbox.** Preview uses `loadFileURL` + `allowingReadAccessTo` so sibling CSS/JS/images load. That is the intended Safari-like hole for the user’s own page. Not a URL-bar browser.
- **JSON vs HTML parsers on huge files.** N2: debounce or bound work; do not parse on every keystroke if that janks.
- **FoldID migration.** Extending `Kind` must not drop persisted Markdown heading/fence folds.
- **`MarkdownDocument` name.** Keeping the class name while it opens JSON is awkward but avoids a risky rename. Rename is out of scope unless it is cheap on the kernel ticket.
- **Wave B scope creep.** Brace folding for TSX/PHP-in-HTML is a tar pit. Requirements already cut HTML islands and JSX-as-elements.
- **iOS document types.** Importer and `Info.plist` must actually list the UTIs or Open will still grey out files (the Markdown-as-plain-text lesson).
- **Default Preview mode vs HTML.** HTML opens in Source so the first frame is foldable text, not a blank WebView.

## Open questions

None blocking. If Wave B slips, that is an execute decision recorded on tickets 8–9, not a new briefing. N5 was overridden 2026-08-24: HTML Preview is a full render.

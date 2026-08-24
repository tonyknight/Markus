# Markus v1.3 — Completion

> Companion to `(2026-08-22) Document kinds Requirements.md`. Written after the board closed (9/9 tickets done) and the work merged to local `main` (`7dff2de`, 2026-08-22). Records what shipped, what was deferred, residual risk, and the human testing this release still needs.

## Summary

v1.3 stops treating every file as Markdown. Markus now detects a closed set of document kinds from UTI/extension, lets the user pin a kind when the extension is wrong, folds those kinds’ real structure on the existing `FoldStore` / TextKit 2 path, and keeps Markdown Preview, GFM, heading/fence folds, and Settings as they were in v1.2.

Wave A (JSON, HTML, SVG, TOML) was the release bar. After those tickets, the kernel was judged solid enough to ship Wave B in the same board: CSS, JavaScript, TypeScript, Swift, PHP, and Shell. Tree-sitter was not used. CotEditor was a behavior reference only.

The automated gate for this board was **Debug build**, not `xcodebuild test`. macOS, iPhone 17, and iPad Pro 13-inch (M5) Debug builds succeeded on the execute branch and again after merge to `main`. The Requirements also require opening real files in the running app. That visual pass was **not** done during execute. The testing plan below is the remaining release gate.

Local `main` was not pushed as part of finish.

## What was done

All nine Tasks Breakdown tickets shipped.

### Kernel (R1–R4, R9, R11, R12)

- **DocumentKind.** Closed set: markdown, json, html, svg, toml, css, javascript, typescript, swift, php, shell. Extension first, then UTI, then markdown. Untitled with no URL is markdown.
- **One document class.** `MarkdownDocument` / `MarkusDocumentController` still host every file. Kind is a session field, not a subclass per language. `typeForContents` no longer forces `net.daringfireball.markdown`.
- **SyntaxProfile.** Each kind returns foldables, outline rows, parse diagnostics, and highlight spans. Markdown wraps today’s `BlockIndex` / cmark path. `FoldID.Kind` is a profile string; v1.2 `"heading"` / `"fence"` records still decode.
- **Pin.** UserDefaults JSON keyed by file path (`KindPin`). Written only on explicit Pin. Untitled has no pin. Open uses `pin ?? extension/UTI`.
- **New.** ⌘N stays Markdown. File → New JSON / HTML / SVG / TOML / CSS / JavaScript / TypeScript / Swift / PHP / Shell create untitled documents of that UTI. Save uses the kind’s default extension unless the user picks another.
- **Kind UI.** Mac Format menu: Document Kind list + Pin/Unpin. iOS: compact toolbar menu on the open file. No inspector pane.
- **Info.plist.** Wave A and Wave B types registered; same `NSDocumentClass`. File importer accepts shipped kinds plus plain text.
- **v1.4 hooks.** `DocumentSession` / `DocumentHost` expose `outlineItems` and `diagnostics`. No new sidebar.

### Wave A (R5–R8, N2, N5, N6)

- **JSON.** Dedicated UTF-8 scanner (not `JSONSerialization` for ranges, not tree-sitter). Objects and arrays fold after the opener line. Invalid JSON does not crash; session gets at least one diagnostic. Source-only; Preview chrome hidden. Save is the UTF-8 buffer; no pretty-print. Scan budget 2 MiB / 50 ms. Non-Markdown kinds skip the Markdown Preview/cmark parse (N2).
- **HTML and SVG.** One tokenizer, two dialects (HTML void/rawtext vs XML/CDATA). Matching end tags fold; void and `/>` do not. Outline is `tag#id.class` when cheap. Preview is a locked WKWebView overlay: JavaScript off, non-persistent store, `loadHTMLString` with `baseURL` nil, content blockers attached to the constructing `WKUserContentController` **before** any load, load only while Preview is visible, fail-closed if rules do not compile. `SessionEditorRepresentable` stays mounted across Source/Preview (v1.1 Settings lesson). HTML/SVG open in Source.
- **TOML.** `[table]` and `[[array-of-tables]]` fold from after the header through the next header (or EOF). Inline `{…}` / `[…]` values are not headers. Outline is table names. Source-only.

### Coloring (R10)

Non-Markdown Source paints keyword / string / comment / number from existing `ThemeTokens` (keyword ← link, string ← fence, number ← inlineCode, comment ← italic). No new Appearance wells. Markdown Source stays v1.2 1:1 body color. Markdown Preview and the HTML/SVG WebView are not recolored by this map.

### Wave B (R13)

Wave A kernel (detection, JSON/HTML folds, Markdown cmark skip, WebView lock-down) was judged solid after tickets 01–07. Wave B shipped in this release rather than slipping.

- **CSS / JS / TS / Swift.** Shared brace matcher. `{…}` that spans past the opener line folds. `.tsx` is TypeScript; JSX tags are not fold units. JS/TS/Swift skip `/…/` regex so braces inside a pattern cannot steal folds.
- **PHP.** `{` blocks only. No HTML-element folds, no `<?php` folds. Heredoc/nowdoc closers accept PHP 7.3 extra tokens (`foo(<<<SQL…SQL)`).
- **Shell.** Kind + keyword/string/comment/number color. Best-effort `{` folds; quotes and `${…}` skipped; unmatched `}` ignored. No indent / `if`/`fi` folds. Must not claim JSON quality.

### Integration

Merged locally to `main` on 2026-08-22 (`7dff2de`). Execute worktree `.worktrees/v1.3-document-kinds` and branch `bora/markus-v1-3-document-kinds` were removed after merge. `bora/markus-v1.2` was left in place.

## What was deferred

These were out of scope or cut on purpose. They are not unfinished tickets on this board.

| Item | Where it lives |
|---|---|
| Inspector chrome (document info, hierarchical outline, warning list) | v1.4 Inspector. v1.3 only exposes outline/diagnostic **data**. |
| LSP, linters, debug, git, plugins, terminal | Non-goals |
| CotEditor source, grammars, syntax-definition editor | Non-goals (N1) |
| Tree-sitter | Not chosen for Wave A or Wave B |
| Side-by-side Source and Preview | Non-goal |
| JSON / TOML / Wave B WebView or “pretty tree” | Non-goal |
| Python, Ruby, Rust, C, YAML-as-a-kind, XML besides SVG | Non-goals (Wave C / briefing cuts) |
| Fence-interior language injection in Markdown | Non-goal; color map may be reused later |
| New Appearance wells / ThemeStore changes | Non-goal; colors derive from existing tokens |
| iOS File → New JSON (etc.) | Mac has the New commands. iOS still opens into a single host; `showsEditor` still requires a file URL. Kind/Pin on the open file is what R12 asked. |
| PHP HTML-island folds | Explicit R13 cut. `{` inside `<style>`/`<script>` in a `.php` file can still fold. |
| JSX tag folds | Explicit R13 cut; braces only |
| Shell indent / `if`/`fi` folds | Optional; not shipped. Brace groups only. |
| Unit-test expansion | N4. Visual open of fixtures is the product gate. |
| Push / GitHub PR | Finish merged locally only |

Minor leftovers that are **not** deferred features, but were left as-is after review:

- Mac Pin/Unpin stay enabled on untitled documents (no-op without a file URL). iOS already disables Pin without a URL.
- Changing kind after Pin does not rewrite the stored pin; relaunch restores the pinned kind until the user Pins again.
- Mac Document Kind menu has no checkmark; iOS does.
- JSON/HTML/TOML/brace scanners copy the full UTF-8 array before applying the size cap.
- Compact JSON keys can share an outline `sourceLine` (the existing outline `ForEach` uses that as `id`).
- `Info.plist` re-declares some system UTIs (css, javascript, swift, php, shell) in addition to document types.

## Risks that remain

1. **No on-screen pass yet (highest).** Tickets closed on build + code review. Requirements commit criteria also asked for a real file of each kind opened in the app. That has not happened. Folds, Preview lock-down, Pin across relaunch, and Markdown non-regression are unverified by eye. Do not ship a build to testers until the plan below is walked.

2. **WebView is untrusted HTML with residual holes.** Script is off, network/file schemes are blocked, and the page does not load until content rules are on the real `WKUserContentController`. Remaining: `data:` URLs are allowed; the SVG wrapper interpolates the raw buffer into an HTML shell. Relative images are expected to break (N5 wins). A content-rule compile failure fail-closes (blank Preview), which is safer than an unlocked load.

3. **Large files are bounded, not free.** Scanners stop at 2 MiB / ~50 ms / foldable caps and emit a warning. `SourceMap` / `UTF16LineOffsets` still walk the buffer. A multi-megabyte JSON/HTML file should not freeze like unbounded cmark, but typing may still hitch. The first UTF-8 copy happens before the byte cap.

4. **Heuristic parsers will mis-fold.** JS regex skip is previous-token plus prefix keywords, not a JS grammar. PHP still folds `{` inside HTML islands. Shell can treat a `'` inside a `<<EOF` body as an opening quote and swallow the rest of the file (degrades, should not crash). TOML space-separated datetimes can emit a false diagnostic. These are acceptable for v1.3 quality if they do not wreck ordinary files; they are not a promise of IDE-grade parse.

5. **Kind pin vs set-kind.** After Pin, Set Kind without pinning again is session-only. Easy to think the new kind will survive relaunch. Document this in release notes or fix later.

6. **Launch Services / Open.** Re-imported system UTIs can confuse ranking. Finder “Open with Markus” for `.html` / `.css` / `.js` needs a human check that Markus appears and that a double-click still does what you want (Owner vs Alternate).

7. **Markdown fold persistence.** Decode of v1.2 `"heading"` / `"fence"` is compatible in code. Reloading a `.md` with previously folded headings after this merge has not been watched.

8. **`MarkdownDocument` name.** The NSDocument class still has that name while it opens JSON. Harmless for users; confusing for the next engineer.

9. **iOS document creation.** There is no iOS New JSON/HTML path. Opening shipped kinds via the importer is the iOS story. Empty-state copy still says “Open a Markdown file.”

## Testing plan for this release

Build is already green. This plan is the **running-app** pass Requirements called out. Use the merged `main` Debug build. Do not treat `xcodebuild test` as a substitute.

### 0. Sanity

- [ ] Launch Markus. Untitled window is Markdown. Settings (⌘,) still opens the v1.2 Preferences window and does not unmount a document.
- [ ] Open an existing `.md` with heading and fence folds you used in v1.2. Preview substitution, GFM tables/alerts, heading/fence chevrons, and Settings look unchanged. Quit and relaunch: those folds should still be there.

### 1. Wave A — JSON

- [ ] Open `package.json` (or similar) from File → Open and from Finder. Kind is JSON. Source/Preview picker is **hidden**. Nested objects/arrays fold; opener line stays visible. Edit a string, Save, reopen: bytes match what you typed (no pretty-print).
- [ ] Break the JSON (delete a `}`). App does not crash. Session still has a diagnostic (Outline menu may be empty; that is OK — data is for v1.4).
- [ ] File → New JSON. Untitled, kind JSON, Source. Save as `scratch.json`.

### 2. Wave A — HTML / SVG

- [ ] Open a small `.html`. Kind HTML, **Source** first. Nested elements with end tags fold; `<br>` / `<img>` / `/>` do not. Flip to Preview: rendered page, **no** URL bar. Session still there (caret/folds intact when you return to Source).
- [ ] Preview of HTML that contains `<script>alert(1)</script>` and `<img src="https://example.com/x.png">`: no alert, no network fetch (Activity Monitor / Charles optional; absence of the image is expected).
- [ ] Open a `.svg`. Source folds groups; Preview shows the drawing inside the locked WebView.
- [ ] Type in Source; Preview updates without destroying the editor (debounce is fine).

### 3. Wave A — TOML

- [ ] Open a `.toml` with several `[tables]` and `[[arrays]]`. Header line stays visible; body folds. Preview hidden. Save round-trips the buffer.

### 4. Kind assignment

- [ ] Open a `.txt` that contains JSON. Default kind is Markdown (or whatever UTI says). Format → Document Kind → JSON, then **Pin Kind**. Quit, reopen the same path: JSON folds. **Unpin Kind**: follows the extension again.
- [ ] Set kind without pinning: session changes; relaunch follows extension (not the session-only choice).
- [ ] ⌘N is Markdown. New HTML / New Swift create the matching untitled types.

### 5. Wave B

- [ ] `.css` — rule / `@media` blocks fold.
- [ ] `.js` — `function outer() { const re = /{/; }` still folds **outer**, not the regex. `replace(/}/g, "")` does not close the enclosing function early.
- [ ] `.ts` / `.tsx` — TypeScript kind; JSX tags are not extra fold units; `{…}` in script folds.
- [ ] `.swift` — `func` / `struct` / closure braces fold.
- [ ] `.php` — `function` / `class` braces fold. `<div>` does not. `foo(<<<SQL\nselect 1\nSQL)` does not swallow the rest of the file.
- [ ] `.sh` — opens as Shell, keywords/comments colored. Brace functions fold if present; a typical script does not crash.

### 6. Coloring

- [ ] JSON keys/strings/numbers are distinguishable in Source (not all body color).
- [ ] HTML tags read as structure when folded.
- [ ] A `.md` in Source is still a single body color (no JSON-style inner roles).

### 7. iOS / iPad

- [ ] Debug build already succeeded; still **open** a `.json` and a `.html` via the in-app Open / importer on iPhone 17 and iPad Pro 13-inch (M5). Compact kind menu can set and pin. HTML Preview uses the same locked WebView. No crash on rotate.

### 8. Do not block on

- Outline UI showing JSON keys (v1.4).
- Pretty-printed JSON on save.
- Perfect PHP-in-HTML or Shell `if`/`fi` folding.
- `xcodebuild test` as a release gate.

### Pass / fail

**Pass:** Markdown looks like v1.2; JSON/HTML/TOML/Wave B open as themselves; HTML Preview does not run script or fetch; Pin survives relaunch; saves are the buffer; no hang on a mid-size `package.json`.

**Fail (block the release):** Markdown Preview or heading/fence folds broken; every file still treated as Markdown; HTML Preview executes script or hits the network; Save rewrites JSON; opening a shipped kind crashes; typing in a few-hundred-KB JSON freezes the UI for seconds.

When this list is checked, the Requirements acceptance criteria for v1.3 are actually met — not only built.

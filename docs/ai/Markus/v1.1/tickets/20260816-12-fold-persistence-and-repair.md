---
id: 20260816-12-fold-persistence-and-repair
title: Fold persistence and repair
type: feature
priority: medium
status: done
created: 2026-08-16
updated: 2026-08-17
closed: 2026-08-17
notes: ''
parent:
depends_on:
- 20260816-04-fold-all-unfold-all-and-fence-placeholder
subtasks:
- id: T1
  title: Add FoldID.anchor (short digest of the block's opening line)
  status: done
- id: T2
  title: Persist fold set per file in app storage
  status: done
- id: T3
  title: Repair fold IDs against anchors when the block index rebuilds
  status: done
plan_status: done
---
## Description

`FoldID` is `kind + startLine`, and rebuilding the block index after an
edit leaves folds pointing at stale line numbers; v1 called for repair
on rebuild and there is none. Separately, `FoldStore` is an in-memory
`Set` and nothing is written — v1 specified per-file persistence in app
state. This ticket lands **before** editing (ticket 13) deliberately:
editing is what breaks stale fold IDs, so repair has to exist before
typing does.

## Acceptance criteria

- [x] Folds persist per file across relaunch, in app storage — not an
      in-memory `Set` (R16).
- [x] `FoldID` gains an `anchor` (short digest of the block's opening
      line) (Data model `FoldID`).
- [x] When the block index is rebuilt after an edit, fold IDs are
      repaired against their anchors rather than left pointing at stale
      line numbers (R17).
- [x] A fold survives an edit made elsewhere in the document (R17).

## Context

- Requirements: R16, R17; Data model `FoldID.anchor`; Constraints
  ("Files remain the source of truth... Folds... live in app storage").
- Planning doc `(2026-08-16) v1.1.md`: F.17, F.18.
- Depends on ticket 04 for the fold service this persists and repairs.
- Ticket 13 (Text input in Source) depends on this ticket — per the
  Requirements Tasks Breakdown, this "lands before editing because
  editing is what breaks stale IDs."

## Subtasks

- [x] Add `anchor: String` to `FoldID`, computed as a short digest of the
      block's opening line.
- [x] Implement per-file fold persistence (app storage, e.g.
      `UserDefaults` keyed by file).
- [x] Implement repair: on block-index rebuild, match existing fold
      anchors against the new index and update `startLine` accordingly.
- [x] Test: fold a block, edit elsewhere in the document, confirm the
      fold survives; relaunch, confirm folds are restored.

## Implementation plan

Status: done
Current task: 

### T01: Add `FoldID.anchor` (short digest of the block's opening line)

Add `anchor: String` to `FoldID` in `Markus/Markus/Markdown/BlockIndex.swift`,
computed in `BlockIndex.build` from the block's opening source line (the
line at `parsedBlock.lines.lowerBound`) via a new `FoldAnchor.digest(_:)`
helper (a small stable FNV-1a hex hash — no new external dependency).
Hoist the existing per-fence `SourceMap(markdown: markdown)` construction
in `build` to a single `let sourceMap` shared by every block (heading and
fence alike need it for the opening-line text), which also happens to fix
the repeated-construction note in the planning doc (P5) as a side effect
of needing it for every block, not just fences. `FoldID.Kind` gains a
`String` raw value so `FoldID` can be `Codable` (needed by T02). Update
`BlockIndexTests.swift`'s three full-struct-equality assertions
(`h2.id == FoldID(kind:startLine:)` etc.), which no longer compile once
`anchor` is required, to assert `kind`/`startLine` plus a new explicit
`anchor == FoldAnchor.digest("<opening line text>")` assertion per block,
and add a test that two blocks with the same opening line text produce
the same anchor while different opening lines differ (live, comparable
values — not a flag, N9).

Files: `Markus/Markus/Markdown/BlockIndex.swift`,
`Markus/MarkusTests/BlockIndexTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/BlockIndexTests`
- [x] done
### T02: Persist fold set per file in app storage

Add `FoldPersistence` (new file `Markus/Markus/Markdown/FoldPersistence.swift`),
following the `RecentDocuments`/`ThemeStore` `UserDefaults`-backed pattern
exactly: `init(defaults: UserDefaults = .standard)`, a single storage key
(`"markus.folds"`) holding a JSON-encoded `[String: [FoldID]]` keyed by
`url.standardizedFileURL.path`, `load(for:)` / `save(_:for:)`. Give
`FoldStore` a `persistence: FoldPersistence` (defaulting to
`FoldPersistence()`, matching every other store's default-to-`.standard`
convention — safe because persistence only ever reads/writes once
`bind(to:)` has been called with a non-nil URL, and no existing call site
does that today) plus `bind(to url: URL?)` (loads the persisted set for
that file, replacing `foldedIDs`) and a private `persist()` called from
`toggle`, `foldAll`, and `unfoldAll` after mutating `foldedIDs`. Wire
`DocumentSession.open(url:)` to call the file's fold restore after
`editor.loadMarkdown(markdown)` (added in T03, since restore also needs
repair against the freshly built index). Test: using an isolated
`UserDefaults(suiteName:)` per the `RecentDocumentsTests` pattern, fold a
block on a `FoldStore` bound to a temp file URL, construct a **second**,
independent `FoldStore`/`DocumentSession` against the same isolated
defaults and the same URL (simulating relaunch), and assert
`foldStore.isFolded(id)` is true on the second instance — live state
after a real reload, not a persisted-flag check that can't fail (N9).

Files: `Markus/Markus/Markdown/FoldPersistence.swift`,
`Markus/Markus/Markdown/FoldStore.swift`,
`Markus/MarkusTests/FoldStoreTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/FoldStoreTests`
- [x] done
### T03: Repair fold IDs against anchors when the block index rebuilds

Add `FoldStore.repair(against blocks: [Block])`: for each currently
folded `FoldID`, find the block whose `id.kind`/`id.anchor` match and
replace the folded entry with that block's (possibly renumbered) `id`;
drop folds whose anchor no longer matches any block (the block was
deleted). Call it from `FoldingSession.syncBlocksFromStorage()` right
after rebuilding `blocks`, so every existing rebuild-after-edit path
(`FoldingTextView.replaceSelection(with:)` today; future typing in
ticket 13) repairs automatically. Add `FoldingSession.restoreFolds(for
url: URL?)` (`foldStore.bind(to: url)` then `repair(against: blocks)`
then `applyFolds()`) and a matching `FoldingTextView.restoreFolds(for:)`
that also calls `ensureLayout()`; call it from
`DocumentSession.open(url:)` right after `editor.loadMarkdown(markdown)`
(completing T02's open-time restore path). Test (the ticket's explicit
acceptance scenario): load a fixture where a foldable heading sits after
another block, fold it, use `FindReplace.search`/`.replace` to edit text
inside the earlier block so it grows by extra lines (shifting the folded
heading's `startLine`), call `syncBlocksFromStorage()` (the real rebuild
path), and assert `foldStore.isFolded(...)` is true for the block found
by its **new** `startLine` in the rebuilt index while the **old**
`FoldID` (stale `startLine`) is absent from `foldedIDs` — live,
post-rebuild state (N9). Also test the open-time path end to end: open a
file, fold a block, `DocumentSession.open(url:)` again on the same file
after editing it on disk to shift lines, and assert the fold is repaired
rather than dropped or stuck stale.

Files: `Markus/Markus/Markdown/FoldStore.swift`,
`Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/Markus/Document/DocumentSession.swift`,
`Markus/MarkusTests/FoldStoreTests.swift`,
`Markus/MarkusTests/FoldingTextViewTests.swift`,
`Markus/MarkusTests/DocumentSessionTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/FoldStoreTests -only-testing:MarkusTests/FoldingTextViewTests -only-testing:MarkusTests/DocumentSessionTests`

### Ticket-scope verify (after T03)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```
- [x] done
## Notes

Append-only running log. Each entry dated.

### 2026-08-17
All three plan tasks complete. T01: FoldID gained anchor: String (an FNV-1a digest of the block's opening source line) plus FoldID.Kind's String raw value; BlockIndex.build now hoists one shared SourceMap per build (also closing the P5 repeated-construction note) and computes each block's anchor from its opening line. T02: new FoldPersistence follows the RecentDocuments/ThemeStore UserDefaults-backed pattern exactly (one JSON blob under "markus.folds", keyed by standardized file path); FoldStore binds to a file URL, restores its persisted set, and persists after every toggle/foldAll/unfoldAll — a real per-file app-storage set, not an in-memory Set (R16). T03: FoldStore.repair(against:) re-matches folded IDs by kind+anchor against a freshly rebuilt block list, replacing stale startLines and dropping folds whose block was deleted; wired into FoldingSession.syncBlocksFromStorage() (today's edit-time rebuild path via find/replace, and typing once ticket 13 lands) and into a new restoreFolds(for:) called from DocumentSession.open(url:) right after loadMarkdown, so persisted folds are bound and repaired against the current index on open (R17). Explicit acceptance-scenario test added: fold block A, edit block B's body via FindReplace so A's startLine shifts, rebuild via syncBlocksFromStorage(), assert live foldStore.isFolded state for the repaired id and absence of the stale one. All tests assert live FoldStore/BlockIndex state (isFolded/foldedIDs/startLine/anchor), never a flag that can't fail (N9). Verify: xcodebuild macOS, iOS Simulator iPhone 17, and iOS Simulator iPad Pro 13-inch (M5) all TEST SUCCEEDED. bora dev lint clean. Working tree clean after 3 commits (T01, T02, T03). AC checkboxes, subtask checkboxes, and status left untouched for the controlling session's independent review per process boundary.

## Review

**2026-08-17 — Verdict: clean.** Reviewed by a fresh subagent against R16, R17, and the `FoldID.anchor` data model entry, independently re-running the touched test suites (`FoldStoreTests`, `FoldingTextViewTests`, `DocumentSessionTests`, `BlockIndexTests`: 20/20 pass) plus the full macOS suite (all green, including UI tests).

Confirmed: `FoldAnchor.digest(_:)` is a pure FNV-1a hash over the opening line's UTF-8 bytes only — no line number folded in, proven directly by a test where two identically-worded headings at different `startLine`s share an anchor; the `SourceMap` hoist from per-fence to per-build introduces no correctness risk (one immutable markdown snapshot per build call); persistence genuinely follows the `RecentDocuments`/`ThemeStore` `UserDefaults` pattern, is genuinely per-file (keyed by standardized path), and survives a real second-instance reload in test; `repair(against:)` matches by `kind`+`anchor`, correctly updates `startLine` on match and correctly drops folds for deleted blocks (rebuilds a fresh set rather than mutating in place); wired into both real production paths (`FoldingSession.syncBlocksFromStorage()` for edit-time rebuild, `DocumentSession.open(url:)` for open-time restore), not just unit-tested in isolation; the ticket's core acceptance scenario (fold A, edit B via real `FindReplace`, rebuild, A survives under its repaired id) is tested end-to-end through production code; all `UserDefaults`-touching tests use isolated per-test suites, no shared-domain pollution; every assertion checks live state (N9). No findings, Minor or otherwise.

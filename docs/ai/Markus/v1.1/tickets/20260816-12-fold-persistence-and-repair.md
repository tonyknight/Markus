---
id: 20260816-12-fold-persistence-and-repair
title: Fold persistence and repair
type: feature
priority: medium
status: in-progress
created: 2026-08-16
updated: 2026-08-17
closed:
notes: ''
parent:
depends_on:
- 20260816-04-fold-all-unfold-all-and-fence-placeholder
subtasks:
- id: T1
  title: Add FoldID.anchor (short digest of the block's opening line)
  status: todo
- id: T2
  title: Persist fold set per file in app storage
  status: todo
- id: T3
  title: Repair fold IDs against anchors when the block index rebuilds
  status: todo
current_task: T02
plan_status: in-progress
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

- [ ] Folds persist per file across relaunch, in app storage — not an
      in-memory `Set` (R16).
- [ ] `FoldID` gains an `anchor` (short digest of the block's opening
      line) (Data model `FoldID`).
- [ ] When the block index is rebuilt after an edit, fold IDs are
      repaired against their anchors rather than left pointing at stale
      line numbers (R17).
- [ ] A fold survives an edit made elsewhere in the document (R17).

## Context

- Requirements: R16, R17; Data model `FoldID.anchor`; Constraints
  ("Files remain the source of truth... Folds... live in app storage").
- Planning doc `(2026-08-16) v1.1.md`: F.17, F.18.
- Depends on ticket 04 for the fold service this persists and repairs.
- Ticket 13 (Text input in Source) depends on this ticket — per the
  Requirements Tasks Breakdown, this "lands before editing because
  editing is what breaks stale IDs."

## Subtasks

- [ ] Add `anchor: String` to `FoldID`, computed as a short digest of the
      block's opening line.
- [ ] Implement per-file fold persistence (app storage, e.g.
      `UserDefaults` keyed by file).
- [ ] Implement repair: on block-index rebuild, match existing fold
      anchors against the new index and update `startLine` accordingly.
- [ ] Test: fold a block, edit elsewhere in the document, confirm the
      fold survives; relaunch, confirm folds are restored.

## Implementation plan

Status: in-progress
Current task: T02

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
- [ ] done
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

## Notes

Append-only running log. Each entry dated.

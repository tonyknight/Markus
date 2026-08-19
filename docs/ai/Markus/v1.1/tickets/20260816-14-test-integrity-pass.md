---
id: 20260816-14-test-integrity-pass
title: Test integrity pass
type: chore
priority: low
status: in-progress
created: 2026-08-16
updated: 2026-08-18
closed:
notes: ''
parent:
depends_on:
- 20260816-13-text-input-in-source
subtasks:
- id: T1
  title: Audit suite for unfalsifiable assertions; delete/rewrite MacOnlyChromeTests
  status: todo
- id: T2
  title: Live-behaviour tests for menus, fold-all, theme, tree, preview
  status: todo
---
## Description

`MacOnlyChromeTests` asserts that `#if os(macOS) true #else false`
evaluates to `true` on macOS — it cannot fail and proves nothing.
Several other chrome tests assert compile-time flags rather than live
view behaviour. This ticket runs last, once every feature it needs to
test against actually exists, and removes or replaces every assertion
that cannot fail.

## Acceptance criteria

- [ ] `MacOnlyChromeTests` and any similar compile-time-flag assertions
      are removed or replaced with live-behaviour tests (I.25).
- [ ] Menu commands, fold-all, theme selection, tree population, and
      Preview rendering all have tests that would fail if the feature
      were removed (I.26).
- [ ] No assertion in the suite can pass unconditionally (N9).
- [ ] Menu items are asserted by validating the built `NSMenu` and the
      responder chain resolving each action, per Testing requirements →
      "How to test UI".
- [ ] The full suite passes on macOS, iPhone simulator, and iPad
      simulator (Success criteria, final bullet).

## Context

- Requirements: N9; Testing requirements → "How to test UI".
- Planning doc `(2026-08-16) v1.1.md`: I.25, I.26.
- Depends on ticket 13 — this is the final ticket in the Tasks
  Breakdown and needs every prior feature (including editing) in place
  to write meaningful live-behaviour tests against.

## Subtasks

- [ ] Audit the suite for assertions that cannot fail; catalogue them.
- [ ] Delete or rewrite `MacOnlyChromeTests` and equivalents.
- [ ] Add/replace tests for menu commands (built `NSMenu` + responder
      chain resolution), fold-all/unfold-all, theme selection, folder
      tree population, and Preview rendering — each asserting live
      behaviour, with at least one assertion that would fail if the
      feature were removed.
- [ ] Run the full suite on all three destinations and confirm green.

## Implementation plan

Status: approved
Current task: T01

Design note (read before touching any test file): the controlling
session already audited the suite for `#if os(macOS)` compile-time-flag
assertions (N9 violations) so T01 does not need to repeat the search
from scratch. The full catalogue:

**Production flags that are pure `#if os(macOS) true #else false #endif`
(or an unconditional `true`) with no live derivation** —
`MacOnlyChrome.minimapIsRequired` (`Document/MacOnlyChrome.swift:12-18`),
`MacDocumentChrome.usesNSDocumentTabbing` and
`.standaloneFileOpenCreatesNewDocument` (`Document/MacDocumentChrome.swift:7-21`),
`MacMinimapChrome.showsMinimap` (`Editor/MacMinimap.swift:126-132`),
`ModeChrome.showsMacTitleBarControl`/`.showsIOSSegmentedControl`
(`Document/ModeChrome.swift:13-26`), `ThemeChrome.showsHoverPreview`
(`Theme/ThemeChrome.swift:9-15`), `ThemeChrome.hostsPickerInSettings`
(`Theme/ThemeChrome.swift:8`, unconditionally `true` — never had two
branches, so it has never been able to fail on any platform, which is
N9's violation in its plainest form). Do **not** delete these
properties themselves — production code that legitimately branches on
platform is fine; N9 is about the *test* asserting a value that cannot
differ from what the compiler already guarantees, not about the
production flag existing.

**Test call sites, catalogued by how much genuine live coverage already
exists alongside them:**

- `MacOnlyChromeTests.swift` (the whole file, `tabsAndMinimapAreMacOnlyAndIOSHasNeither`) —
  **wholly tautological, zero live behaviour**, and every claim it makes
  is already covered live elsewhere: minimap's real rendering/structure
  is covered by `MacMinimapTests.swift` (extensive, ticket 09/10 work);
  tabbing's real behaviour is covered by `MacTabsTests.swift`'s
  `markdownDocumentPrefersTabsAndReusesFoldingSession` (asserts real
  `first.configuredTabbingMode`, distinct `FoldingSession`s per real
  `MarkdownDocument`). Delete this file outright — nothing needs
  replacing, the coverage already exists under its real name elsewhere.
- `MacTabsTests.swift:10-19` (`macUsesNSDocumentTabbingNotSwiftUITabBar`) —
  same shape, same redundancy with the very next test in the same file.
  Delete this one test function; keep the rest of the file (it's
  already live-behaviour, e.g. `openingSecondFileUsesNSDocumentNotSessionReplace`
  at line 87 opens two real files and asserts real `DocumentHost` state).
- `MacTabsTests.swift:88` and `:139` — single redundant lines
  (`#expect(MacDocumentChrome.standaloneFileOpenCreatesNewDocument)` /
  `#expect(!...)`) sitting at the top of two already-fully-live tests
  (`openingSecondFileUsesNSDocumentNotSessionReplace`,
  `iOSChromeOpenReplacesSingleSession`) that go on to open real files
  and assert real `DocumentHost`/session state. Delete just these two
  lines; the surrounding test bodies are the real coverage and stay.
- `ModeChromeTests.swift:71-72, 89-90, 92-93` — three pairs of
  `#expect(ModeChrome.showsMacTitleBarControl)` /
  `.showsIOSSegmentedControl` lines embedded inside otherwise-live tests
  (`macTitleBarPickerBindsToExclusiveHostMode`,
  `iOSSegmentedControlBindsToExclusiveHostModeWithoutMacTitleBar`, both
  of which already do real `ModeChrome.select`/`host.mode` assertions).
  Replace, don't just delete: the file has **no** test proving the mac
  title bar control actually is the *only* mode control materialized in
  a real window (contrast `MacTitleBarChromeTests.swift`'s
  `macTitleBarToolbarHasOnlyTheModePickerAndNothingElse`, which is this
  ticket's own best precedent — it already replaced a similar tautology
  with a real `NSToolbar.items.count` check, with a doc comment
  explaining exactly why per N9). Build a comparable live check here:
  a real `MarkdownDocument`'s toolbar contains the mode picker item and
  nothing that would only exist for the other platform's control.
- `ThemePickerTests.swift:125-132` (`settingsHostThePickerAndHoverPreviewIsMacOnly`) —
  both halves are tautological (`hostsPickerInSettings` is
  unconditionally `true`, `showsHoverPreview` is the `#if` pattern).
  Delete the `hostsPickerInSettings` assertion (nothing to test — it is
  not platform-conditional, has no live counterpart to check against).
  For hover preview: `ThemeChrome.preview(_:on:)`'s *effect* is already
  live-tested elsewhere in this file (lines ~211-222, calling it
  directly and asserting real `host` state changes) but the *gating* —
  that `ThemeCard`'s `onHover` closure only calls `ThemeChrome.preview`
  when `showsHoverPreview` is true — has no live test on either
  platform. This is a genuine, if small, coverage gap: decide whether
  to add a live check (e.g. constructing a `ThemeCard` and invoking its
  `onHover` closure directly, asserting `host`'s previewed-theme state
  changes only under the platform-correct condition) or judge it
  low-value SwiftUI-plumbing not worth testing directly, the way this
  codebase already treats `.onHover`/hit-testing elsewhere (per ticket
  13's research notes on this suite's established pattern of testing
  underlying methods directly rather than simulating platform events) —
  record whichever call is made and why in Notes.

**AC 2's "menu commands, fold-all, theme selection, tree population,
and Preview rendering all have tests that would fail if the feature
were removed"** is, per this audit, **already substantially satisfied**
by tests earlier tickets already wrote — this ticket's T02 should
confirm each, not necessarily write new ones: menu commands and
fold-all/unfold-all via responder-chain resolution are covered by
`MacMainMenuTests.swift`'s
`foldAllAndUnfoldAllResolveThroughTheResponderChainAndActuallyFoldTheDocument`
and its sibling `customEditAndOpenFolderActionsResolveThroughTheResponderChainToTheDocument`
(both already do exactly what the "How to test UI" testing requirement
asks: validate the built `NSMenu` and resolve through the real responder
chain); theme selection by `ThemePickerTests.swift`/`CustomThemeTests.swift`;
tree population by `FolderChromeTests.swift`'s
`folderImporterUsesFolderTypeAndTreeVisibilityFollowsSession` (opens a
real folder, asserts real tree visibility); Preview rendering by the
extensive `PreviewSubstitution`/`PreviewParsing`-adjacent test files
from tickets 08-09. T02 should re-read each to confirm it would
actually fail if the feature were removed (N9's own bar), not assume
the audit above is exhaustive — if a genuine gap turns up, add a test
for it, scoped small.

### T01: Audit suite for unfalsifiable assertions; delete/rewrite MacOnlyChromeTests

Confirm the catalogue in the design note by re-reading each cited file
(cheap, since exact file/line references are given) — add anything the
audit above missed (grep the whole `Markus/MarkusTests/` directory for
`#if os(macOS)` blocks whose only content on both branches is a bare
`true`/`false` literal feeding directly into `#expect`, and for any
`static let`/unconditional-`true` production constant asserted without
a counterfactual). Delete `MacOnlyChromeTests.swift` outright (its
claims are redundant with `MacMinimapTests.swift` and `MacTabsTests.swift`,
per the design note). Delete `MacTabsTests.swift`'s
`macUsesNSDocumentTabbingNotSwiftUITabBar` test function and the two
redundant single-line flag assertions at `:88`/`:139` (leaving the rest
of those test bodies untouched — they are real coverage). Record the
confirmed catalogue in this ticket's Notes.

Files: `Markus/MarkusTests/MacOnlyChromeTests.swift` (delete),
`Markus/MarkusTests/MacTabsTests.swift`

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/MacTabsTests`

### T02: Live-behaviour tests for menus, fold-all, theme, tree, preview

Replace `ModeChromeTests.swift`'s three tautological line-pairs
(`:71-72`, `:89-90`, `:92-93`) with one real check (per the design
note's `MacTitleBarChromeTests` precedent): a real `MarkdownDocument`'s
materialized toolbar/window contains the mode-switching control
appropriate to the platform and not the other platform's, asserted via
the real view/toolbar tree rather than `ModeChrome.showsMacTitleBarControl`
read back directly. Fix `ThemePickerTests.swift:125-132`: delete the
`hostsPickerInSettings` half; for `showsHoverPreview`, either add a
live gating check or record the judgment call to leave it untested with
its rationale (design note). Re-confirm (read, don't just trust the
audit) that `MacMainMenuTests.swift`, `ThemePickerTests.swift`/
`CustomThemeTests.swift`, `FolderChromeTests.swift`, and the Preview
rendering test files each contain at least one assertion that would
fail if the corresponding feature were removed or broken (N9's actual
bar — not "a test exists" but "the test is falsifiable in the right
direction"); add a small test for any genuine gap found, scoped to just
that gap. Run the full suite on all three destinations per this
ticket's final Acceptance Criterion.

Files: `Markus/MarkusTests/ModeChromeTests.swift`,
`Markus/MarkusTests/ThemePickerTests.swift`, plus any file where T02's
re-confirmation pass finds a genuine gap

Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test -only-testing:MarkusTests/ModeChromeTests -only-testing:MarkusTests/ThemePickerTests`

### Ticket-scope verify (after T02)

```
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

## Notes

Append-only running log. Each entry dated.

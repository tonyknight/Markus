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

### 2026-08-18

**T01.** Re-read every file/line cited in the design note's catalogue
and confirmed it exactly: `MacOnlyChrome.minimapIsRequired`,
`MacDocumentChrome.usesNSDocumentTabbing`/
`.standaloneFileOpenCreatesNewDocument`, `MacMinimapChrome.showsMinimap`,
`ModeChrome.showsMacTitleBarControl`/`.showsIOSSegmentedControl`,
`ThemeChrome.showsHoverPreview`/`.hostsPickerInSettings` are all either
pure `#if os(macOS) true #else false #endif` or (for
`hostsPickerInSettings`) unconditional `true` with no counterfactual —
confirmed via direct reads of `Document/MacOnlyChrome.swift`,
`Document/MacDocumentChrome.swift`, `Editor/MacMinimap.swift`,
`Document/ModeChrome.swift`, `Theme/ThemeChrome.swift`. Deleted
`MacOnlyChromeTests.swift` outright (its claims are redundant with
`MacMinimapTests.swift` and `MacTabsTests.swift`, per the design note).
Deleted `MacTabsTests.swift`'s `macUsesNSDocumentTabbingNotSwiftUITabBar`
and the two single-line flag assertions at the top of
`openingSecondFileUsesNSDocumentNotSessionReplace` and
`iOSChromeOpenReplacesSingleSession`, leaving their real live bodies
untouched.

Extended the audit with a grep across `Markus/MarkusTests/` for
`#expect(true)`/`#expect(false)` and for `#if os(macOS)` blocks whose
only content is a bare bool literal into `#expect`, per T01's own
instruction to "add anything the audit above missed." Found two the
catalogue didn't list: `MarkusTests.swift`'s scaffold-generated
`#expect(true)` (the plainest possible N9 violation, unconditionally
true with no derivation at all) — deleted the file; and a single
embedded `#expect(MacMinimapChrome.showsMinimap)` line inside
`MacMinimapTests.swift`'s otherwise fully live
`minimapUsesCurrentModeAndCompressesFoldedPackedY` (only compiled under
`#if os(macOS)`, so it reduces to `#expect(true)` on this platform) —
deleted just that line, same treatment as the catalogued single-line
cases. No other `#if os(macOS)` block in the suite reduces to a bare
bool literal, and no other unconditional-`true` production constant is
asserted anywhere in `Markus/Markus/` — confirmed by grep.

**T02.** Replaced `ModeChromeTests.swift`'s three tautological
`showsMacTitleBarControl`/`showsIOSSegmentedControl` line-pairs
(former `:71-72`, `:89-90`, `:92-93`) with one new test,
`macTitleBarToolbarsSoleItemIsGenuinelyTheSegmentedModePicker`, modeled
directly on `MacTitleBarChromeTests.macTitleBarToolbarHasOnlyTheModePickerAndNothingElse`:
materializes a real `MarkdownDocument`'s window/toolbar and asserts the
sole toolbar item's materialized view subtree contains a real AppKit
segmented control, not just that a lone item exists (that exclusivity
claim was already proven by `MacTitleBarChromeTests`; this test adds
the item's *identity*). TDD: wrote the test, then temporarily swapped
the toolbar's `DocumentModePicker` for a plain `Button` in
`ContentView.swift` and reran — the new test failed for the right
reason (RED, no segmented-control descendant found), then restored the
picker and confirmed GREEN. `ContentView.swift` has no net diff.

Fixed `ThemePickerTests.swift`'s `settingsHostThePickerAndHoverPreviewIsMacOnly`:
deleted it outright rather than partially. `hostsPickerInSettings` had
no live counterpart (unconditionally `true`, never platform-conditional).
For `showsHoverPreview`'s *gating* (whether `ThemeCard`'s `onHover`
closure calls `ThemeChrome.preview` only when the flag is true):
judged this **not worth a live test** and left it untested. Rationale:
the gate is a single inline `guard ThemeChrome.showsHoverPreview else { return }`
inside `ThemePickerView.body`'s closures, not independently callable
without either duplicating that one-line guard in the test (testing a
copy, not the real wiring) or invasively refactoring production code
just to make it testable. More fundamentally, `showsHoverPreview` is
fixed at compile time per platform, so within any single-platform test
binary the gate can only ever be exercised in the one direction that
platform's build takes — there is no way to observe both "gated off"
and "gated on" behaviour in one run, so a single-platform test of the
gate would itself be exactly as unfalsifiable as the tautology it
would replace. This matches the codebase's established pattern (noted
in ticket 13's research) of not simulating platform hover/hit-test
events and instead testing the underlying method directly —
`ThemeChrome.preview(_:on:)`'s real effect stays covered by
`macHoverPreviewChangesOnlyTheProxysTokensNeverTheRealDocument`
elsewhere in the same file.

Re-confirmed (read in full, not assumed) that each of the AC's five
named areas has genuinely falsifiable coverage: menu commands and
fold-all/unfold-all via `MacMainMenuTests.swift` (real `NSMenu` built
via `MacMainMenu.build()`, real responder-chain walk via
`resolveAndPerform`, real `FoldStore` state assertions in
`foldAllAndUnfoldAllResolveThroughTheResponderChainAndActuallyFoldTheDocument`);
theme selection via `ThemePickerTests.swift`/`CustomThemeTests.swift`
(real `ThemeStore`/`CustomTheme.tokens` value assertions, a real
AppKit mouse-event dispatch test for card selection); tree population
via `FolderChromeTests.swift` plus the more extensive
`MarkdownFolderTreeTests.swift`/`FolderSessionTests.swift` (real
folder enumeration, real security-scoped bookmark round-trips); Preview
rendering via `PreviewSubstitutionTests.swift`/`PreviewRenderingTests.swift`
(extensive, real GFM substitution assertions per element). No genuine
gap found beyond what T01/T02 already fixed — no new test files added.

**Verify.** T01's and T02's own scoped verify commands passed
individually. Ticket-scope verify (full suite, all three destinations)
passed clean with zero failures:
- macOS: `** TEST SUCCEEDED **` (135.9s), 243 passed, 0 failed.
- iOS Simulator, iPhone 17: `** TEST SUCCEEDED **` (116.8s), 147
  passed, 0 failed.
- iOS Simulator, iPad Pro 13-inch (M5): `** TEST SUCCEEDED **` (177.9s),
  147 passed, 0 failed.

`bora dev lint "Markus/v1.1"` run after each ticket-file edit; only
the known pre-existing, out-of-scope error on ticket 08
(`current_task 'T08' is not a task id`) reported — unrelated to this
ticket's files.

## Review

### 2026-08-18

**Verdict: Minor (clean to ship).** Commit range `2dc16af..HEAD`
(bed7b4d T01, 66e664c T02, 8b70baa Notes) reviewed in full against the
design note's catalogue, the AC, and N9. No Critical or Important
findings.

**T01 (bed7b4d).** Read the full diff. Deletions match the plan
exactly: `MacOnlyChromeTests.swift` removed outright (its sole test was
wholly tautological, both branches of `#if os(macOS)` feeding literal
booleans, no live derivation); `MacTabsTests.swift` lost only
`macUsesNSDocumentTabbingNotSwiftUITabBar` and the two single-line flag
reads at the top of `openingSecondFileUsesNSDocumentNotSessionReplace`
and `iOSChromeOpenReplacesSingleSession` — the real bodies of those two
tests (opening real files, asserting real `DocumentHost` state) are
byte-for-byte untouched. Independently verified the two extra findings
claimed beyond the catalogue: `MarkusTests.swift` was in fact nothing
but `struct MarkusTests { @Test func scaffoldCompiles() { #expect(true) } }`
— a scaffold-generated tautology with zero real coverage riding on it,
correctly deleted; and `MacMinimapTests.swift` lost exactly one line
(`#expect(MacMinimapChrome.showsMinimap)`) from the top of
`minimapUsesCurrentModeAndCompressesFoldedPackedY`, whose remaining body
(loading real markdown, setting real modes, asserting real bar
geometry) is untouched. Both claims check out.

**T02 (66e664c).** `ModeChromeTests.swift`'s new
`macTitleBarToolbarsSoleItemIsGenuinelyTheSegmentedModePicker` is
genuine: it builds a real `MarkdownDocument`, calls
`makeWindowControllers()`, forces layout on a real `NSWindow`, pulls
the real `NSToolbar`, and recursively walks the toolbar item's actual
materialized `NSView` subtree looking for a class name containing
"SegmentedControl" — not a mock, not a type/count check that could
pass without the control present. Ran it and its siblings
(`ModeChromeTests`, `ThemePickerTests`, `MacTabsTests`,
`MacMinimapTests`) via `-only-testing:` on macOS myself this session:
`** TEST SUCCEEDED **`, all pass. `git diff 2dc16af..HEAD --
Markus/Markus/ContentView.swift` is empty and `ContentView.swift` does
not appear in either commit's changed-files list — the claimed RED
temporary-swap-then-revert left no net production diff, confirmed
empirically rather than just trusted. Confirmed `DocumentModePicker`
(`Document/ModeChrome.swift:66`) does use `.pickerStyle(.segmented)`,
so the new test's target actually exists and the RED/GREEN claim is
plausible on its face.

**`ThemePickerTests.swift`'s `showsHoverPreview` judgment call.**
Legitimate scope call, not a dodge, but the recorded rationale
overstates its own case. The plan's design note explicitly framed this
as a choice ("decide whether to add a live check ... or judge it
low-value ... record whichever call is made and why") — it did not
mandate the fix, so declining it is squarely within what the ticket
itself pre-authorized. However, the Notes argument that a
single-platform test of the gate "would itself be exactly as
unfalsifiable as the tautology it would replace" is not quite right: a
test that constructs a real `ThemeCard`, invokes its `onHover` closure,
and asserts `host`/`store` state actually changed via
`ThemeChrome.preview` would still be a live, falsifiable assertion on
whichever platform the suite is compiled for (it would fail if the
closure stopped calling `preview`, or flipped the hover/unhover
argument) — it just couldn't prove the cross-platform *gating* in one
binary, which was never what the design note asked for. The file
already has a working precedent for testing `ThemeCard`'s closures via
real dispatched AppKit events without duplicating any guard
(`clickOnCardSwatchDispatchesRealAppKitEventThatInvokesOnSelect`,
line ~148) — the Notes entry doesn't address why that route wasn't
viable for hover the way it was for click. This is worth a mention for
whoever next touches theme hover, but since the ticket's own plan
sanctioned "leave it untested, with rationale" as an equally valid
outcome, and the actual coverage gap is small (the gating logic is a
single inline `guard`), this stays Minor, non-blocking.

**AC re-confirmation.** Spot-checked three of the five claimed areas
directly (not just trusting the Notes): `MacMainMenuTests.swift`'s
`foldAllAndUnfoldAllResolveThroughTheResponderChainAndActuallyFoldTheDocument`
opens a real document, resolves `performFoldAll`/`performUnfoldAll`
through the actual responder chain, and asserts real `FoldStore`
fold-state per block — would fail if fold-all broke.
`FolderChromeTests.swift`'s
`folderImporterUsesFolderTypeAndTreeVisibilityFollowsSession` opens a
real temp folder and a real lone file and asserts
`FolderChrome.showsTree`/`host.isFolderTreeVisible` flips correctly
between them — would fail if tree-visibility logic broke.
`PreviewSubstitutionTests.swift`'s
`previewModeHidesHeadingMarkupPunctuation` loads real markdown into a
real `FoldingTextView`, renders it, and asserts the rendered paragraph
text and the *un*touched source buffer — would fail if substitution
broke. All three are genuinely falsifiable, not "doesn't crash"
smoke tests. No gap found.

**N9 completeness (independent grep pass, current suite state).**
`grep -rn "#expect(true)\|#expect(false)"` across
`Markus/MarkusTests/` returns nothing. A Python scan of
`Markus/Markus/` for `#if os(macOS) <bool> #else <bool> #endif`
production properties found exactly the seven already-catalogued flags
(`MacOnlyChrome`, `ModeChrome` x2, `MacDocumentChrome` x2,
`ThemeChrome.showsHoverPreview`, `MacMinimapChrome.showsMinimap`) and
no others; a separate grep for unconditional `static let ... = true`
found only `ThemeChrome.hostsPickerInSettings`. Grepping the test
suite for any remaining reference to any of these flags turns up only
doc-comment mentions in `ModeChromeTests.swift` (explaining what the
new test replaces), no live assertions. Confirms the Notes' own claim
that nothing else reduces to a bare-literal tautology.

**Commit hygiene / TDD evidence.** All three commits follow
`{ticket-id} {task-id}: {title}` (T01/T02) and
`{ticket-id}: {description}` (Notes-only) format correctly. T02's
commit message documents the RED (temporary `Button` swap, confirmed
failure for the right reason) then GREEN (restored, passing) cycle;
`ContentView.swift`'s absence from the commit's changed-file list is
independent confirmation the swap was genuinely reverted, not just
claimed.

No findings block ticket completion. The one Minor item (hover-gating
judgment call rationale) is worth a note for future maintainers but
does not need rework before this ticket — and the whole board's last
ticket — is marked done.

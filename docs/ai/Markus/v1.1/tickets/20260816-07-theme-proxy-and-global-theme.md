---
id: 20260816-07-theme-proxy-and-global-theme
title: Theme proxy and global theme
type: feature
priority: medium
status: in-progress
created: 2026-08-16
updated: 2026-08-17
closed:
notes: ''
parent:
depends_on:
- 20260816-06-settings-surface
subtasks:
- id: T1
  title: Single proxy document below the preset + custom cards
  status: todo
- id: T2
  title: Hover-to-preview into the proxy; click-to-apply
  status: todo
- id: T3
  title: Isolate and fix card selection (suspect FoldingTextView-in-Button)
  status: todo
- id: T4
  title: App-scoped ThemeStore broadcasting to all open documents
  status: todo
---
## Description

The theme picker currently renders a miniature editor inside every card
and repaints the real document on hover — heavy and jarring — and cards
cannot currently be selected at all (root cause not yet isolated; a
suspect is `FoldingTextView` embedded inside each card's `Button`).
Separately, each `MarkdownDocument` builds its own `DocumentHost` and
therefore its own `ThemeStore`, so two Mac tabs can disagree on theme.
This ticket replaces the per-card preview with a single proxy document,
fixes selection, and makes the theme store app-scoped so a change
broadcasts to every open window and tab.

## Acceptance criteria

- [ ] Six preset cards plus custom sit above a single proxy document;
      hovering a card previews that theme in the proxy only; clicking
      applies it (R8; C.9).
- [ ] Card selection works — proven working, not assumed (R8; C.10).
- [ ] Selecting a theme applies it to **every open window and tab**
      immediately (R9; J.27).
- [ ] The choice persists across relaunch (R8).
- [ ] `ThemeStore` is a single app-scoped store, not one per
      `DocumentHost`; a change broadcasts to every open document.

## Context

- Requirements: R8, R9; Architecture component 6 "Theme store and
  picker"; Data model `Theme` (app-scoped, not per window).
- Planning doc `(2026-08-16) v1.1.md`: C.9, C.10, J.27.
- Depends on ticket 06 — the picker lives inside the settings surface's
  themes category.
- Non-goal: the six theme palettes themselves are unchanged — only the
  picker's behaviour changes.

## Subtasks

- [ ] Replace per-card miniature editors with a single proxy document
      view below the cards.
- [ ] Wire hover-to-preview (into the proxy only) and click-to-apply.
- [ ] Isolate the card-selection bug; fix it (check whether moving to a
      single proxy already dissolves it, per the planning doc's
      hypothesis).
- [ ] Promote `ThemeStore` to an app-scoped singleton; broadcast changes
      to every open `DocumentHost`.
- [ ] Persist the applied theme (`UserDefaults`) and confirm it survives
      relaunch.

## Implementation plan

Status: done
Current task: 

### T01: Pure-SwiftUI card swatch, proven card selection via real AppKit event dispatch
Root-cause investigation (done before writing this plan, via a throwaway
NSHostingView + synthetic NSEvent spike, discarded after use): a
`ThemeCard`'s `Button` fails to invoke `onSelect` when the point clicked
falls over the embedded `ThemeSampleView` (the per-card
`FoldingTextView`/`NSViewRepresentable`), **even though that view's own
`hitTest` already returns `nil`** (confirmed via the existing
`themeCardSampleViewDoesNotStealHitsOrFirstResponder` test — the leaf
view correctly declines the hit, but something upstream in AppKit's
hit-test recursion still fails to route the event to the SwiftUI
Button). Swapping the embed for a plain, *opaque* SwiftUI view (a
`Color`-filled swatch) makes the exact same click dispatch correctly;
the planning doc's suspect (C.10) is confirmed as the real cause, not
assumed. (Aside: a fully-transparent `Color.clear` swatch was also
observed to fail hit-testing in the same harness — an unrelated SwiftUI
quirk, avoided by giving the new swatch a real background fill, never
`.clear`.)
Fix: add a new pure-SwiftUI `ThemeSwatch` view (`ThemeChrome.swift`) that
paints `ThemeTokens.background` plus a few color bars for
heading/body/link — no `NSViewRepresentable`/`UIViewRepresentable`
anywhere in it — and use it inside `ThemeCard` in place of
`ThemeSampleView`. `ThemeCard` becomes internal (was `private`) so it is
directly testable. Proof test (new, macOS-only): host a real `ThemeCard`
in an `NSHostingView` inside a real, key `NSWindow`, synthesize a
genuine `NSEvent.leftMouseDown`/`leftMouseUp` pair at the swatch's
on-screen point, dispatch via `window.sendEvent(_:)`, and assert the
card's `onSelect` closure actually ran — a real dispatched AppKit event,
not a direct function call and not a flag that can't fail (N9). RED
confirmed against the current `ThemeSampleView`-embedding `ThemeCard`
(real assertion failure: the closure never ran), GREEN after swapping in
`ThemeSwatch`. `ThemeSampleView`/`ThemeChrome.makeCardSampleView` stay
for now (T02 repurposes them as the single proxy) (R8; C.10; subtasks
"Replace per-card miniature editors..." and "Isolate the card-selection
bug; fix it...").
Files: `Markus/Markus/Theme/ThemeChrome.swift`,
new/updated `Markus/MarkusTests/ThemePickerTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' -only-testing:MarkusTests/ThemePickerTests test`
(macOS-only chrome change, no shared-file edits this task)
- [ ] todo
- [x] done

### T02: Single proxy document below the cards; hover previews into it only
Renamed `ThemeSampleView`/`ThemeChrome.makeCardSampleView`/
`FoldingTextView.configureAsThemeCardSample()` to
`ThemeProxyRepresentable`/`ThemeChrome.makeProxyView`/
`configureAsThemeProxy()` and placed exactly one instance below the
preset+custom grid (and below the custom controls) in `ThemePickerView`,
bound to `host.themeStore.displayedTokens` (hover ?? selection — the
property already existed). Decoupled hover from the real document:
`DocumentHost.previewTheme(_:)` now only updates
`themeStore.beginHover`/`endHover` and calls `objectWillChange.send()`
— it no longer calls `session.editor.setTheme`, so hovering a card never
repaints the real open document, only the proxy below the cards (R8;
C.9). Renamed the private `applyDisplayedTheme()` to
`applyCommittedTheme()` (now reads `themeStore.committedTokens`, not
`displayedTokens`) and kept it wired from `applyTheme`,
`setCustomBackground`, `setCustomTextStyle`, and every `init` — those
are all genuine commits, not hover, so the real document should still
repaint immediately for them. Rewrote
`macHoverPreviewChangesTokensWithoutPersistingUntilApply` (renamed
`macHoverPreviewChangesOnlyTheProxysTokensNeverTheRealDocument`; RED
confirmed by stashing the `DocumentHost.swift` change and re-running —
real assertion failure, not a compile error) to assert
`host.session.editor.tokens` stays at the committed theme throughout
hover while `store.displayedTokens` (the proxy's data source) reflects
the hovered theme, reverting to committed on `preview(nil, ...)`.
Files: `Markus/Markus/Theme/ThemeChrome.swift`,
`Markus/Markus/Editor/FoldingTextView.swift`,
`Markus/Markus/Document/DocumentHost.swift`,
`Markus/MarkusTests/ThemePickerTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`
(`DocumentHost.swift`/`FoldingTextView.swift` are shared, non-`#if`-
guarded — also run `-destination 'platform=iOS Simulator,name=iPhone
17'` and `-destination 'platform=iOS Simulator,name=iPad Pro 13-inch
(M5)'`)
- [ ] todo
- [x] done

### T03: App-scoped `ThemeStore` singleton, broadcasting to every open document
Add `ThemeStore.shared` (a `static let`, same `UserDefaults.standard`-
backed default `init()`). Wire the two real window/tab entry points to
it explicitly: `MarkdownDocument.init()` (mac, one `DocumentHost` per
document/tab today) and `AppRootView` (iOS/iPadOS, one per scene) both
pass `themeStore: ThemeStore.shared` through the existing
`init(session:recents:themeStore:)` initializer — so every real document
window/tab/scene shares the identical `ThemeStore` instance. Deliberately
*not* touched: `DocumentHost`'s other, already-existing convenience
initializers (`init()`, `init(recents:)`, `init(session:recents:)`) keep
creating a fresh, isolated `ThemeStore()` exactly as before — dozens of
pre-existing tests across other files construct `DocumentHost` through
those for unrelated concerns (folders, mode, zoom, tabs...) and must not
start sharing one global mutable store, which would be incidental
coupling with no test coverage of its own. Add a dedicated
`ThemeStore.themeChanged: PassthroughSubject<Void, Never>`, sent (after
the property write, not via `@Published`'s pre-mutation `objectWillChange`
timing) from `select`, `setCustomBackground`, and `setCustomTextStyle`
only — deliberately not from `beginHover`/`endHover`, so a hover in one
window never forces every other open document to reparse/repaint (that
would just relocate the "heavy and jarring" bug T02 removes, rather than
fixing it). `DocumentHost.observe()` subscribes to `themeChanged` and
re-applies the store's `committedTokens` to `session.editor` — this is
what makes every open document's real editor actually repaint when
*any* document commits a theme change, not just the one that made it
(R9; J.27; subtask "Promote ThemeStore to an app-scoped singleton...").
Test (new, in `ThemePickerTests.swift`): construct two `DocumentHost`s
sharing one explicit, isolated `ThemeStore` instance (the existing
`hostWithStore` pattern, called twice with the same `store` — this
exercises the identical production wiring/subscription path, just
pointed at a test-isolated `UserDefaults` suite instead of `.standard`),
call `ThemeChrome.select(_:on:)` on the *first* host, and assert the
*second* host's `session.editor.tokens` changed too — a real broadcast
via the Combine subscription, not two hosts independently reading the
same stored value (N9). Also add a macOS-only identity test constructing
two real `MarkdownDocument()`s and asserting
`ObjectIdentifier(first.host.themeStore) ==
ObjectIdentifier(second.host.themeStore)`, proving the actual production
wiring (not a test substitute) shares one instance.
Files: `Markus/Markus/Theme/ThemeStore.swift`,
`Markus/Markus/Document/DocumentHost.swift`,
`Markus/Markus/Document/MarkdownDocument.swift`,
`Markus/Markus/MarkusApp.swift`,
`Markus/MarkusTests/ThemePickerTests.swift`,
`Markus/MarkusTests/MacTabsTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`
(`DocumentHost.swift`/`ThemeStore.swift` are shared, non-`#if`-guarded —
also run `-destination 'platform=iOS Simulator,name=iPhone 17'` and
`-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`)
- [ ] todo
- [x] done

### T04: Confirm relaunch persistence under app scope; full-suite verify; Notes
No new production code expected. Add a test that selects a theme through
one `DocumentHost` sharing an explicit store (mirroring `ThemeStore.shared`'s
wiring), then constructs a *fresh* `ThemeStore(defaults:)` from the same
`UserDefaults` suite (simulating relaunch, matching the existing
"`restored`" pattern already used by
`selectingNamedThemeAppliesTokensAndPersistsIdNotMarkdown`) and asserts
the new store's `selection`/`displayedTokens` come back correctly —
confirming persistence still works now that the store is app-scoped
rather than per-`DocumentHost` (R8). Run the full three-destination
suite once more after all tasks, run `bora dev lint`, then append the
dated `## Notes` entry summarizing the root-cause finding and the fix.
Files: `Markus/MarkusTests/ThemePickerTests.swift`
Verify: `xcodebuild -project Markus/Markus.xcodeproj -scheme Markus -destination 'platform=macOS' test`,
`-destination 'platform=iOS Simulator,name=iPhone 17' test`,
`-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test`
- [ ] todo
- [x] done

## Notes

Append-only running log. Each entry dated.

### 2026-08-17
All 4 plan tasks (T01-T04) complete and committed.

**Root cause of "cards cannot be selected" (T01), isolated empirically, not
assumed.** Before writing any fix, spiked a throwaway harness (discarded
after use, not committed): host a real `ThemeCard` in an `NSHostingView`
inside a real, key `NSWindow`, synthesize a genuine
`NSEvent.leftMouseDown`/`leftMouseUp` pair, and dispatch it via
`window.sendEvent(_:)` at the swatch's on-screen point. Against the
unmodified `ThemeCard` (which embedded `ThemeSampleView`, a
`FoldingTextView`/`NSViewRepresentable`), the click never reached
`onSelect` — reproducing the bug. Two controlled variants ruled out red
herrings before accepting the finding: (1) a non-key `NSWindow` also
fails to dispatch clicks to *any* SwiftUI `Button` regardless of content
(confirmed with a trivial `Button("Tap")`) — so the window must be key,
which the real fix's test now does; (2) a fully-transparent `Color.clear`
swatch placeholder *also* failed to dispatch, an unrelated SwiftUI
quirk — so the real fix's swatch fill is never `.clear`. With both
confounders controlled for, swapping only the embedded `FoldingTextView`
for a plain, opaque SwiftUI view flipped the same click from failing to
passing, and swapping it back (keeping the key window and opaque-content
fixes) reproduced the failure again. This confirms the planning doc's
suspect (C.10) *was* the actual cause: a `Button` containing an
`NSViewRepresentable`/`UIViewRepresentable` subview fails to dispatch
clicks landing over that subview's region to the button's own action —
even though the embedded view's own `hitTest` already returns `nil`
(`themeCardSampleViewDoesNotStealHitsOrFirstResponder`, unchanged,
proved that in isolation but wasn't sufficient — AppKit's hit-test
recursion doesn't fall through to the SwiftUI button the way that test
implied it would). The fix (a new pure-SwiftUI `ThemeSwatch`, no
embedded view of any kind) dissolves the bug by construction rather than
patching around it. The committed proof test
(`clickOnCardSwatchDispatchesRealAppKitEventThatInvokesOnSelect`) is a
permanent regression guard, not throwaway — it's macOS-only, hosts the
real (now `internal`, was `private`) `ThemeCard`, and asserts the
dispatched closure actually ran (N9: a real dispatched AppKit event, not
a direct call to `onSelect`/`ThemeChrome.select`).

**T01** also made `ThemeCard` `internal` for testability and added
`ThemeSwatch` (color bars from `ThemeTokens`, drawn entirely in SwiftUI).
**T02** renamed the (now per-card-unused) `ThemeSampleView`/
`makeCardSampleView`/`configureAsThemeCardSample` to
`ThemeProxyRepresentable`/`makeProxyView`/`configureAsThemeProxy` and
placed exactly one instance below the preset+custom grid in
`ThemePickerView`, bound to `themeStore.displayedTokens`. Decoupled hover
from the real document: `DocumentHost.previewTheme(_:)` no longer calls
`session.editor.setTheme` — hovering now only ever repaints the proxy,
never the real open document (R8; C.9). Renamed the private
`applyDisplayedTheme()` to `applyCommittedTheme()`, now reading
`themeStore.committedTokens` rather than `displayedTokens`.
**T03** added `ThemeStore.shared` (a `static let`) and wired the two real
production entry points — `MarkdownDocument.init()` (mac) and
`AppRootView` (iOS/iPadOS) — to it explicitly via the existing
`init(session:recents:themeStore:)` initializer, so every real
window/tab/scene shares one instance. Deliberately left `DocumentHost`'s
other convenience initializers creating a fresh, isolated `ThemeStore()`
as before, so the many pre-existing tests across other files that
construct `DocumentHost` for unrelated concerns (folders, mode, zoom,
tabs) don't start sharing one global mutable store with no coverage of
their own. Added `ThemeStore.themeChanged` (`PassthroughSubject<Void,
Never>`), sent *after* the property write (unlike `@Published`, which
publishes before the value is actually stored — a real timing hazard if
a subscriber reads the property synchronously) from `select`,
`setCustomBackground`, and `setCustomTextStyle` only, deliberately never
from `beginHover`/`endHover` — broadcasting hover would just relocate
T02's "heavy and jarring" bug across every open window instead of fixing
it. `DocumentHost.observe()` subscribes to `themeChanged` and re-applies
`committedTokens`; `applyTheme`/`setCustomBackground`/
`setCustomTextStyle` on `DocumentHost` now purely delegate to the store,
relying entirely on this subscription to repaint — proved load-bearing
by temporarily disabling just the subscription (keeping everything else
compiling) and confirming the broadcast test, and *also* the pre-existing
select/custom-theme tests, all failed for the right reason before
re-enabling it. New tests: two `DocumentHost`s sharing one explicit,
isolated `ThemeStore` (the identical wiring pattern production uses with
`.shared`, just pointed at a test suite) show a selection on one host
repainting the other's `session.editor.tokens` via the real Combine
subscription (not two hosts independently reading the same stored
value); a macOS-only identity test constructs two real
`MarkdownDocument()`s and asserts they resolve to the same
`ThemeStore.shared` instance, exercising the actual production wiring,
not a substitute.
**T04** added a persistence-across-simulated-relaunch test with two
windows sharing the store (theme selected via one, a *fresh*
`ThemeStore(defaults:)` from the same `UserDefaults` suite comes back
with the same selection/tokens) — no new production code, since the
existing `UserDefaults`-backed persistence in `ThemeStore` was already
scope-agnostic and needed no change once the store itself became
app-scoped.

Destinations run: T01 was macOS-only chrome with no shared-file changes,
so macOS alone sufficed for that task's commit; T02-T04 all touched
`DocumentHost.swift` and/or `ThemeStore.swift` (shared, non-`#if`-guarded)
so all three destinations ran for each. Final full-suite verify (fresh,
this session, after all four tasks): `-destination 'platform=macOS'
test` -> TEST SUCCEEDED (31.7s); `-destination 'platform=iOS
Simulator,name=iPhone 17' test` -> TEST SUCCEEDED (77.8s); `-destination
'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test` -> TEST
SUCCEEDED (83.6s). `bora dev lint` -> OK, no issues. Working tree fully
committed after this notes commit. Acceptance-criteria/Subtask body
checkboxes intentionally left unchecked and ticket `status:` frontmatter
left `in-progress`, per this project's precedent (tickets 02/05/06) —
checking those off, marking done, and running `bora-review` is the
controlling session's job after independent review, not run here.

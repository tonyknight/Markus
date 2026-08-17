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

Status: in-progress
Current task: T03

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

## Notes

Append-only running log. Each entry dated.

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct ThemePickerTests {
    private func isolatedStore() -> ThemeStore {
        let suite = "markus.theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ThemeStore(defaults: defaults)
    }

    private func pinnedStore(family: ThemeFamily = .nord, variant: ThemeVariant = .light) -> ThemeStore {
        let store = isolatedStore()
        store.setFollowSystem(false)
        store.selectNamed(family, variant: variant)
        return store
    }

    private func hostWithStore(_ store: ThemeStore) -> DocumentHost {
        DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.theme.host.\(UUID().uuidString)")!),
            themeStore: store
        )
    }

    @Test func selectingNamedThemeAppliesTokensAndPersistsIdNotMarkdown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-theme-\(UUID().uuidString).md")
        let markdown = GFMPreviewFixture.markdown
        try Data(markdown.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = pinnedStore()
        let host = hostWithStore(store)
        host.openPicked(url)
        #expect(store.selection == .named(.nord))
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))

        ThemeChrome.selectNamed(.github, variant: .light, on: host)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .github, variant: .light))
        #expect(store.selection == .named(.github))
        #expect(store.persistedSelectionID == "github")
        #expect(try String(contentsOf: url, encoding: .utf8) == markdown)

        let restored = ThemeStore(defaults: store.defaults)
        #expect(restored.selection == .named(.github))
        #expect(restored.followSystem == false)
        #expect(restored.pinnedVariant == .light)
        #expect(restored.displayedTokens == NamedThemeCatalog.tokens(for: .github, variant: .light))
    }

    @Test func customCardAppliesDerivedTokensAndPersistsCustomId() {
        let store = isolatedStore()
        let host = hostWithStore(store)
        #if os(macOS)
        let background = NSColor(srgbRed: 0.20, green: 0.12, blue: 0.10, alpha: 1)
        #else
        let background = UIColor(red: 0.20, green: 0.12, blue: 0.10, alpha: 1)
        #endif
        store.setCustomBackground(background)
        store.setCustomTextStyle(.dark)
        ThemeChrome.select(.custom, on: host)

        let expected = CustomTheme.tokens(background: background, textStyle: .dark)
        #expect(host.session.editor.tokens == expected)
        #expect(store.persistedSelectionID == "custom")
        #expect(store.selection == .custom)
    }

    /// Proves the app-scoped broadcast (R9; J.27): two `DocumentHost`s
    /// sharing one `ThemeStore` instance — the exact production wiring
    /// `MarkdownDocument`/`AppRootView` use with `ThemeStore.shared`,
    /// just pointed at an isolated `UserDefaults` suite for test hygiene
    /// — must both repaint when *either* one commits a theme change. This
    /// exercises the real `ThemeStore.themeChanged` -> `DocumentHost`
    /// Combine subscription, not two hosts independently reading the same
    /// stored value (N9).
    @Test func selectingOnOneHostBroadcastsToAnotherHostSharingTheSameStore() {
        let store = pinnedStore()
        let first = hostWithStore(store)
        let second = hostWithStore(store)
        #expect(first.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))
        #expect(second.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))

        ThemeChrome.selectNamed(.github, variant: .dark, on: first)

        #expect(first.session.editor.tokens == NamedThemeCatalog.tokens(for: .github, variant: .dark))
        #expect(second.session.editor.tokens == NamedThemeCatalog.tokens(for: .github, variant: .dark))
    }

    /// Confirms persistence still works now that `ThemeStore` is app-scoped
    /// rather than one-per-`DocumentHost` (R8): a theme selected while
    /// *two* windows/tabs share one store must still be there after a
    /// simulated relaunch (a fresh `ThemeStore` reading the same
    /// `UserDefaults` suite — the same mechanism `ThemeStore.shared` would
    /// use against `.standard` across a real relaunch).
    @Test func selectionMadeWhileTwoWindowsShareTheStorePersistsAcrossSimulatedRelaunch() {
        let store = pinnedStore()
        let first = hostWithStore(store)
        let second = hostWithStore(store)

        ThemeChrome.selectNamed(.solarized, variant: .light, on: second)
        #expect(first.session.editor.tokens == NamedThemeCatalog.tokens(for: .solarized, variant: .light))
        #expect(store.persistedSelectionID == "solarized")

        // Simulated relaunch: a brand new ThemeStore, no DocumentHost
        // sharing memory with `store`, reading the same UserDefaults suite.
        let relaunched = ThemeStore(defaults: store.defaults)
        #expect(relaunched.selection == .named(.solarized))
        #expect(relaunched.followSystem == false)
        #expect(relaunched.pinnedVariant == .light)
        #expect(relaunched.displayedTokens == NamedThemeCatalog.tokens(for: .solarized, variant: .light))
        #expect(relaunched.committedTokens == NamedThemeCatalog.tokens(for: .solarized, variant: .light))
    }

    @Test func setThemePaintsEditorCanvasWithTokenBackground() {
        let view = FoldingTextView()
        let dark = NamedThemeCatalog.tokens(for: .nord, variant: .dark)
        view.setTheme(dark)
        #expect(view.canvasBackground.isEqual(dark.background))
        #if os(macOS)
        #expect(view.layer?.backgroundColor == dark.background.cgColor)
        #else
        #expect(view.backgroundColor?.isEqual(dark.background) == true)
        #endif
    }

    @Test func themeProxyViewIsReadOnlyAndNeverStealsHitsOrFirstResponder() {
        let proxy = ThemeChrome.makeProxyView(tokens: NamedThemeCatalog.tokens(for: .nord, variant: .light))
        #if os(macOS)
        proxy.frame = NSRect(x: 0, y: 0, width: 160, height: 88)
        #expect(proxy.hitTest(NSPoint(x: 80, y: 44)) == nil)
        #expect(!proxy.acceptsFirstResponder)
        #else
        #expect(!proxy.isUserInteractionEnabled)
        #endif
    }

    #if os(macOS)
    /// Proves card selection actually works end to end: a genuine AppKit
    /// mouse-down/mouse-up pair, synthesized and dispatched through a real
    /// `NSWindow`'s `sendEvent(_:)` at the swatch's on-screen point, must
    /// reach the card's `onSelect` closure. This is deliberately *not* a
    /// direct call to `onSelect` or `ThemeChrome.select` — that would only
    /// prove the closure works, not that a real click reaches it (N9;
    /// R8; C.10 — "selection must be proven working, not assumed"). Before
    /// this ticket's fix, the same harness against the old
    /// `ThemeSampleView`-embedding card reproduced the reported bug: the
    /// click was silently swallowed and `onSelect` never ran, even though
    /// the embedded view's own `hitTest` already returned `nil`.
    @Test func clickOnCardSwatchDispatchesRealAppKitEventThatInvokesOnSelect() {
        var selected: ThemeSelection?
        let card = ThemeCard(
            title: ThemeFamily.github.pickerTitle(variant: .light),
            tokens: NamedThemeCatalog.tokens(for: .github, variant: .light),
            isSelected: false,
            onSelect: { selected = .named(.github) },
            onHover: { _ in }
        )
        .frame(width: 180, height: 140)

        let hostingView = NSHostingView(rootView: card)
        hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 140)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        // A point inside the swatch band (the card's top ~88pt) — the
        // region the old embedded FoldingTextView occupied.
        let point = NSPoint(x: 90, y: 70)
        let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        let upEvent = NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        window.sendEvent(downEvent)
        window.sendEvent(upEvent)
        window.orderOut(nil)

        #expect(selected == .named(.github))
    }

    /// Hovering a card must preview into the proxy document only — the
    /// real open document's editor must never repaint on hover (R8; C.9:
    /// "hover repaints the real document, which is both heavy and
    /// jarring"). The proxy's data source, `themeStore.displayedTokens`,
    /// is what must change; `host.session.editor.tokens` (the real
    /// document) must stay pinned to the committed theme throughout.
    @Test func macHoverPreviewChangesOnlyTheProxysTokensNeverTheRealDocument() {
        let store = pinnedStore(family: .nord, variant: .light)
        let host = hostWithStore(store)
        ThemeChrome.selectNamed(.nord, variant: .light, on: host)
        #expect(store.persistedSelectionID == "nord")
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))

        let hovered = NamedThemeCatalog.tokens(for: .nord, variant: .dark)
        ThemeChrome.preview(hovered, on: host)
        #expect(store.displayedTokens == hovered)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))
        #expect(store.persistedSelectionID == "nord")
        #expect(store.selection == .named(.nord))

        ThemeChrome.preview(nil, on: host)
        #expect(store.displayedTokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))
        #expect(store.persistedSelectionID == "nord")

        ThemeChrome.preview(NamedThemeCatalog.tokens(for: .monokai, variant: .dark), on: host)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .nord, variant: .light))
        ThemeChrome.selectNamed(.monokai, variant: .dark, on: host)
        #expect(store.persistedSelectionID == "monokai")
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .monokai, variant: .dark))
    }
    #endif
}

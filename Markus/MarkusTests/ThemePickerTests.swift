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

        let store = isolatedStore()
        let host = hostWithStore(store)
        host.openPicked(url)
        #expect(store.selection == .named(.daylight))
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .daylight))

        ThemeChrome.select(.named(.harbor), on: host)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .harbor))
        #expect(store.selection == .named(.harbor))
        #expect(store.persistedSelectionID == "harbor")
        #expect(try String(contentsOf: url, encoding: .utf8) == markdown)

        let restored = ThemeStore(defaults: store.defaults)
        #expect(restored.selection == .named(.harbor))
        #expect(restored.displayedTokens == NamedThemeCatalog.tokens(for: .harbor))
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

    @Test func setThemePaintsEditorCanvasWithTokenBackground() {
        let view = FoldingTextView()
        let lampblack = NamedThemeCatalog.tokens(for: .lampblack)
        view.setTheme(lampblack)
        #expect(view.canvasBackground.isEqual(lampblack.background))
        #if os(macOS)
        #expect(view.layer?.backgroundColor == lampblack.background.cgColor)
        #else
        #expect(view.backgroundColor?.isEqual(lampblack.background) == true)
        #endif
    }

    @Test func settingsHostThePickerAndHoverPreviewIsMacOnly() {
        #expect(ThemeChrome.hostsPickerInSettings)
        #if os(macOS)
        #expect(ThemeChrome.showsHoverPreview)
        #else
        #expect(!ThemeChrome.showsHoverPreview)
        #endif
    }

    @Test func themeProxyViewIsReadOnlyAndNeverStealsHitsOrFirstResponder() {
        let proxy = ThemeChrome.makeProxyView(tokens: NamedThemeCatalog.tokens(for: .daylight))
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
            title: "Harbor",
            tokens: NamedThemeCatalog.tokens(for: .harbor),
            isSelected: false,
            onSelect: { selected = .named(.harbor) },
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

        #expect(selected == .named(.harbor))
    }

    /// Hovering a card must preview into the proxy document only — the
    /// real open document's editor must never repaint on hover (R8; C.9:
    /// "hover repaints the real document, which is both heavy and
    /// jarring"). The proxy's data source, `themeStore.displayedTokens`,
    /// is what must change; `host.session.editor.tokens` (the real
    /// document) must stay pinned to the committed theme throughout.
    @Test func macHoverPreviewChangesOnlyTheProxysTokensNeverTheRealDocument() {
        let store = isolatedStore()
        let host = hostWithStore(store)
        ThemeChrome.select(.named(.daylight), on: host)
        #expect(store.persistedSelectionID == "daylight")
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .daylight))

        ThemeChrome.preview(.named(.meadow), on: host)
        #expect(store.displayedTokens == NamedThemeCatalog.tokens(for: .meadow))
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .daylight))
        #expect(store.persistedSelectionID == "daylight")
        #expect(store.selection == .named(.daylight))

        ThemeChrome.preview(nil, on: host)
        #expect(store.displayedTokens == NamedThemeCatalog.tokens(for: .daylight))
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .daylight))
        #expect(store.persistedSelectionID == "daylight")

        ThemeChrome.preview(.named(.fog), on: host)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .daylight))
        ThemeChrome.select(.named(.fog), on: host)
        #expect(store.persistedSelectionID == "fog")
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .fog))
    }
    #endif
}

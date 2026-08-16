import Foundation
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
        #expect(!ThemeChrome.presentsSettingsAsModalSheet)
        #else
        #expect(!ThemeChrome.showsHoverPreview)
        #expect(ThemeChrome.presentsSettingsAsModalSheet)
        #endif
    }

    @Test func themeCardSampleViewDoesNotStealHitsOrFirstResponder() {
        let sample = ThemeChrome.makeCardSampleView(tokens: NamedThemeCatalog.tokens(for: .daylight))
        #if os(macOS)
        sample.frame = NSRect(x: 0, y: 0, width: 160, height: 88)
        #expect(sample.hitTest(NSPoint(x: 80, y: 44)) == nil)
        #expect(!sample.acceptsFirstResponder)
        #else
        #expect(!sample.isUserInteractionEnabled)
        #endif
    }

    #if os(macOS)
    @Test func macHoverPreviewChangesTokensWithoutPersistingUntilApply() {
        let store = isolatedStore()
        let host = hostWithStore(store)
        ThemeChrome.select(.named(.daylight), on: host)
        #expect(store.persistedSelectionID == "daylight")

        ThemeChrome.preview(.named(.meadow), on: host)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .meadow))
        #expect(store.persistedSelectionID == "daylight")
        #expect(store.selection == .named(.daylight))

        ThemeChrome.preview(nil, on: host)
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .daylight))
        #expect(store.persistedSelectionID == "daylight")

        ThemeChrome.preview(.named(.fog), on: host)
        ThemeChrome.select(.named(.fog), on: host)
        #expect(store.persistedSelectionID == "fog")
        #expect(host.session.editor.tokens == NamedThemeCatalog.tokens(for: .fog))
    }
    #endif
}

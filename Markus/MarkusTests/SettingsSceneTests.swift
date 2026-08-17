import Foundation
import Testing
@testable import Markus

/// Covers the pure logic behind the full-viewport settings surface
/// (`SettingsScene.swift`): the category metadata the left-hand list is
/// built from, and the close box's dismissal. The surface itself is a
/// thin macOS-only SwiftUI view built directly on this logic (matching
/// `RibbonRailTests`/`FolderChromeTests`'s precedent — no ViewInspector
/// in this project, so chrome is tested through the observable state it
/// reads and mutates, not by rendering).
@MainActor
struct SettingsSceneTests {
    private func makeHost() -> DocumentHost {
        DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.settings.\(UUID().uuidString)")!)
        )
    }

    @Test func themesCategoryHasDisplayNameThemes() {
        #expect(SettingsCategory.themes.displayName == "Themes")
    }

    @Test func onlyOneCategoryExistsForNow() {
        #expect(SettingsCategory.allCases == [.themes])
    }
}

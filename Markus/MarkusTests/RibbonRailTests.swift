import Foundation
import Testing
@testable import Markus

/// Covers the host-state that drives the left ribbon rail (macOS-only
/// chrome): the hamburger's library-panel toggle and the gear's settings
/// entry point. The rail itself is a thin SwiftUI view built directly on
/// this state (see `RibbonRail.swift`), so testing the state is testing
/// the feature — matching how `FolderChromeTests`/`MacOnlyChromeTests`
/// already cover this codebase's other SwiftUI-only chrome.
@MainActor
struct RibbonRailTests {
    private func makeHost() -> DocumentHost {
        DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.ribbon.\(UUID().uuidString)")!)
        )
    }

    @Test func libraryPanelStartsClosedAndHamburgerTogglesIt() {
        let host = makeHost()
        #expect(!host.isLibraryPanelOpen)
        host.toggleLibraryPanel()
        #expect(host.isLibraryPanelOpen)
        host.toggleLibraryPanel()
        #expect(!host.isLibraryPanelOpen)
    }

    @Test func gearPresentsSettings() {
        let host = makeHost()
        #expect(!host.isSettingsPresented)
        host.presentSettings()
        #expect(host.isSettingsPresented)
    }
}

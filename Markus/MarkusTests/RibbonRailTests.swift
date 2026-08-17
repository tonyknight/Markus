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

    @Test func openingAFolderAutoOpensTheLibraryPanelAndHamburgerCanStillCloseIt() throws {
        let host = makeHost()
        #expect(!host.isLibraryPanelOpen)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-ribbon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Notes\n".utf8).write(to: root.appendingPathComponent("notes.md"))

        // Opening a folder (Open Folder… or Recents) auto-opens the panel.
        host.openFolder(root)
        #expect(host.isLibraryPanelOpen)

        // The hamburger can still manually close it even with a folder
        // session present — toggling is independent of session state.
        host.toggleLibraryPanel()
        #expect(!host.isLibraryPanelOpen)
    }

    @Test func singleFileOpenLeavesTheLibraryPanelClosed() throws {
        let host = makeHost()
        let lone = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-ribbon-lone-\(UUID().uuidString).md")
        try Data("# Lone\n".utf8).write(to: lone)
        defer { try? FileManager.default.removeItem(at: lone) }

        host.openPicked(lone)
        #expect(!host.isLibraryPanelOpen)
    }

    @Test func emptyStateActionPresentsTheFolderImporterWithoutAFolderSession() {
        let host = makeHost()
        #expect(host.folderSession == nil)
        #expect(!host.isFolderImporterPresented)

        LibraryChrome.openFolderFromEmptyState(on: host)

        #expect(host.isFolderImporterPresented)
    }
}

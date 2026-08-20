import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Markus

@MainActor
struct FileImporterChromeTests {
    @Test func notPresentedWhenNeitherFlagIsSet() {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.fileimporter.\(UUID().uuidString)")!)
        )
        #expect(!FileImporterChrome.isPresented(for: host))
    }

    @Test func fileFlagAlonePresentsWithMarkdownTypesAndOpensTheFile() throws {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.fileimporter.\(UUID().uuidString)")!)
        )
        host.isImporterPresented = true
        #expect(FileImporterChrome.isPresented(for: host))
        #expect(!FileImporterChrome.allowedContentTypes(for: host).contains(.folder))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-fileimporter-\(UUID().uuidString).md")
        try Data("# Hi\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        FileImporterChrome.handle(.success([url]), isFolder: false, on: host)

        // macOS opens standalone files as a new NSDocument/window rather
        // than mutating this host's session (see MacTabsTests), so assert
        // via the recents trail the open path actually leaves behind.
        #expect(host.recents.items.map(\.url.standardizedFileURL).contains(url.standardizedFileURL))
        #expect(!host.isImporterPresented)
        #expect(!host.isFolderImporterPresented)
        #expect(host.errorMessage == nil)
    }

    @Test func folderFlagAlonePresentsWithFolderTypeAndOpensTheFolder() throws {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.fileimporter.\(UUID().uuidString)")!)
        )
        host.isFolderImporterPresented = true
        #expect(FileImporterChrome.isPresented(for: host))
        #expect(FileImporterChrome.allowedContentTypes(for: host) == FolderChrome.folderContentTypes)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-fileimporter-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileImporterChrome.handle(.success([root]), isFolder: true, on: host)

        #expect(host.folderSession?.rootURL == root)
        #expect(!host.isImporterPresented)
        #expect(!host.isFolderImporterPresented)
        #expect(host.errorMessage == nil)
    }

    @Test func settingPresentedFalseClearsBothFlags() {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.fileimporter.\(UUID().uuidString)")!)
        )
        host.isImporterPresented = true
        host.isFolderImporterPresented = true
        FileImporterChrome.setPresented(false, on: host)
        #expect(!host.isImporterPresented)
        #expect(!host.isFolderImporterPresented)
    }

    @Test func failureSetsKindAppropriateErrorMessageAndClearsFlags() {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.fileimporter.\(UUID().uuidString)")!)
        )
        host.isFolderImporterPresented = true
        FileImporterChrome.handle(.failure(CocoaError(.fileReadUnknown)), isFolder: true, on: host)
        #expect(host.errorMessage == "Could not open folder.")
        #expect(!host.isFolderImporterPresented)

        host.isImporterPresented = true
        FileImporterChrome.handle(.failure(CocoaError(.fileReadUnknown)), isFolder: false, on: host)
        #expect(host.errorMessage == "Could not open file.")
        #expect(!host.isImporterPresented)
    }

    // `.fileImporter`'s `isPresented` binding `set(false)` and its
    // `onCompletion` handler both fire on dismissal, in an order SwiftUI
    // doesn't guarantee — `ContentView` used to read `host
    // .isFolderImporterPresented` fresh *inside* `handle`, which could
    // already be cleared by the time it ran, mislabeling a folder-open
    // failure as a file-open failure. `handle` now takes `isFolder`
    // explicit, captured by the caller before dismissal can race it —
    // this proves the explicit parameter wins even when the published
    // flag has already been cleared to `false` by the time `handle` runs.
    @Test func handleUsesTheExplicitIsFolderParameterEvenWhenThePublishedFlagAlreadyClearedFirst() {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.fileimporter.\(UUID().uuidString)")!)
        )
        host.isFolderImporterPresented = true
        // Simulates the binding's set(false) winning the race and firing
        // before the completion handler does.
        host.isFolderImporterPresented = false

        FileImporterChrome.handle(.failure(CocoaError(.fileReadUnknown)), isFolder: true, on: host)
        #expect(host.errorMessage == "Could not open folder.")
    }
}

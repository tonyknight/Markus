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

        FileImporterChrome.handle(.success([url]), on: host)

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

        FileImporterChrome.handle(.success([root]), on: host)

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
        FileImporterChrome.handle(.failure(CocoaError(.fileReadUnknown)), on: host)
        #expect(host.errorMessage == "Could not open folder.")
        #expect(!host.isFolderImporterPresented)

        host.isImporterPresented = true
        FileImporterChrome.handle(.failure(CocoaError(.fileReadUnknown)), on: host)
        #expect(host.errorMessage == "Could not open file.")
        #expect(!host.isImporterPresented)
    }
}

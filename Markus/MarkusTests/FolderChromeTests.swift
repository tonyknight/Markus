import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Markus

@MainActor
struct FolderChromeTests {
    @Test func folderImporterUsesFolderTypeAndTreeVisibilityFollowsSession() throws {
        #expect(FolderChrome.folderContentTypes.contains(.folder))
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.folder.chrome.\(UUID().uuidString)")!)
        )
        #expect(!host.isFolderImporterPresented)
        #expect(!FolderChrome.showsTree(for: host))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-folder-chrome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Notes\n".utf8).write(to: root.appendingPathComponent("notes.md"))

        host.openFolder(root)
        #expect(FolderChrome.showsTree(for: host))
        #expect(host.isFolderTreeVisible)

        let lone = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-folder-chrome-lone-\(UUID().uuidString).md")
        try Data("# Lone\n".utf8).write(to: lone)
        defer { try? FileManager.default.removeItem(at: lone) }
        host.openPicked(lone)
        #expect(!FolderChrome.showsTree(for: host))
        #expect(!host.isFolderTreeVisible)
    }
}

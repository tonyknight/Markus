import Foundation
import Testing
@testable import Markus

@MainActor
struct FolderSessionTests {
    private func makeFolderFixture() throws -> (root: URL, notes: URL, nested: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-folder-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let notes = root.appendingPathComponent("notes.md")
        try Data("# Notes\n".utf8).write(to: notes)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let nested = sub.appendingPathComponent("page.markdown")
        try Data("# Page\n".utf8).write(to: nested)
        try Data("skip\n".utf8).write(to: root.appendingPathComponent("ignore.txt"))
        return (root, notes, nested)
    }

    private func isolatedRecents() -> RecentDocuments {
        RecentDocuments(defaults: UserDefaults(suiteName: "markus.folder.\(UUID().uuidString)")!)
    }

    @Test func openFolderThenSelectChildOpensFileAndKeepsTree() throws {
        let fixture = try makeFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let host = DocumentHost(recents: isolatedRecents())
        host.openFolder(fixture.root)

        #expect(host.folderSession?.rootURL.standardizedFileURL == fixture.root.standardizedFileURL)
        let names = host.folderSession?.tree.map(\.name) ?? []
        #expect(names.contains("notes.md"))
        #expect(names.contains("sub"))
        #expect(host.isFolderTreeVisible)

        host.openTreeFile(fixture.nested)
        #expect(host.session.fileURL?.standardizedFileURL == fixture.nested.standardizedFileURL)
        #expect(host.session.editor.string == "# Page\n")
        #expect(host.isFolderTreeVisible)
        #expect(host.folderSession != nil)
        #expect(host.errorMessage == nil)
    }

    @Test func openSingleMarkdownFileHidesFolderTree() throws {
        let fixture = try makeFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lone = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-lone-\(UUID().uuidString).md")
        try Data("# Lone\n".utf8).write(to: lone)
        defer { try? FileManager.default.removeItem(at: lone) }

        let host = DocumentHost(recents: isolatedRecents())
        host.openFolder(fixture.root)
        host.openTreeFile(fixture.notes)
        #expect(host.isFolderTreeVisible)

        host.openPicked(lone)
        #expect(host.session.fileURL?.standardizedFileURL == lone.standardizedFileURL)
        #expect(host.folderSession == nil)
        #expect(!host.isFolderTreeVisible)
        #expect(host.session.editor.string == "# Lone\n")
    }

    @Test func openRecentFolderResolvesBookmarkAndRebuildsTree() throws {
        let fixture = try makeFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let recents = isolatedRecents()
        recents.record(url: fixture.root, isFolder: true)
        let item = try #require(recents.items.first)
        #expect(item.isFolder)

        let host = DocumentHost(recents: recents)
        host.openRecent(item)
        #expect(host.errorMessage == nil)
        #expect(host.isFolderTreeVisible)
        #expect(host.folderSession?.rootURL.standardizedFileURL == fixture.root.standardizedFileURL)
        #expect(host.folderSession?.tree.map(\.name).contains("notes.md") == true)
    }

    @Test func openRecentStaleFolderSetsErrorWithoutCrashing() {
        let recents = isolatedRecents()
        recents.record(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString)", isDirectory: true),
            bookmarkData: Data([0x00, 0xFF]),
            isFolder: true
        )
        let host = DocumentHost(recents: recents)
        host.openRecent(recents.items[0])
        #expect(host.errorMessage != nil)
        #expect(host.folderSession == nil)
    }
}

import Foundation
import Testing
@testable import Markus

struct RecentDocumentsTests {
    private func uniqueTempMarkdownURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-recent-\(UUID().uuidString).md")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "markus.recents.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func recordsFileURLsAndRecallsThemOnMac() throws {
        let url = uniqueTempMarkdownURL()
        try Data("# Recent\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recents = RecentDocuments(defaults: isolatedDefaults())
        recents.record(url: url)

        #expect(recents.items.map(\.url) == [url])
        let opened = try recents.startAccessing(recents.items[0])
        #expect(opened == url)
        recents.stopAccessing(opened)
    }

    @Test func staleBookmarkFailsCleanlyWithoutCrashing() throws {
        let url = uniqueTempMarkdownURL()
        try Data("# Gone\n".utf8).write(to: url)
        let bookmark = try url.bookmarkData(options: .minimalBookmark)
        try FileManager.default.removeItem(at: url)

        let recents = RecentDocuments(defaults: isolatedDefaults())
        recents.record(url: url, bookmarkData: bookmark)

        #expect(throws: RecentDocumentsError.self) {
            _ = try recents.startAccessing(recents.items[0])
        }
    }

    @Test func openingRecentWithBookmarkResolvesURL() throws {
        let url = uniqueTempMarkdownURL()
        try Data("# Bookmark\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let bookmark = try url.bookmarkData(options: .minimalBookmark)

        let recents = RecentDocuments(defaults: isolatedDefaults())
        recents.record(url: url, bookmarkData: bookmark)
        let opened = try recents.startAccessing(recents.items[0])
        #expect(opened.standardizedFileURL == url.standardizedFileURL)
        recents.stopAccessing(opened)
    }

    @Test func recordCreatesBookmarkAndStartAccessingReturnsUsableURL() throws {
        let url = uniqueTempMarkdownURL()
        let markdown = "# Bookmark round trip\n"
        try Data(markdown.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recents = RecentDocuments(defaults: isolatedDefaults())
        recents.record(url: url)

        let item = try #require(recents.items.first)
        #expect(item.bookmarkData != nil)
        let opened = try recents.startAccessing(item)
        #expect(FileManager.default.isReadableFile(atPath: opened.path))
        #expect(try String(contentsOf: opened, encoding: .utf8) == markdown)
        recents.stopAccessing(opened)
    }
}

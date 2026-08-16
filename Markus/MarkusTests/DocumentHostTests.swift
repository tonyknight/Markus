import Foundation
import Testing
@testable import Markus

@MainActor
struct DocumentHostTests {
    private func uniqueTempMarkdownURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-host-\(UUID().uuidString).md")
    }

    @Test func openPickedFileLoadsEditorAndRecordsRecent() throws {
        let url = uniqueTempMarkdownURL()
        let markdown = "# Picked\n"
        try Data(markdown.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recents = RecentDocuments(defaults: UserDefaults(suiteName: "markus.host.\(UUID().uuidString)")!)
        let host = DocumentHost(recents: recents)
        host.openPicked(url)

        #expect(host.session.editor.string == markdown)
        #expect(host.session.fileURL == url)
        #expect(host.recents.items.map(\.url.standardizedFileURL) == [url.standardizedFileURL])
        #expect(host.errorMessage == nil)
    }

    @Test func openPickedMissingFileSetsErrorWithoutCrashing() {
        let missing = uniqueTempMarkdownURL()
        let host = DocumentHost()
        host.openPicked(missing)
        #expect(host.errorMessage != nil)
        #expect(host.session.editor.string.isEmpty)
    }
}

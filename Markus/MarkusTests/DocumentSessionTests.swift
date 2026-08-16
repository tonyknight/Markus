import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct DocumentSessionTests {
    private func uniqueTempMarkdownURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-session-\(UUID().uuidString).md")
    }

    @Test func openLoadsUTF8IntoTextStorageAndFoldingTextView() throws {
        let url = uniqueTempMarkdownURL()
        let markdown = "# Hello\n\nCafé — UTF-8.\n"
        try Data(markdown.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)

        #expect(session.fileURL == url)
        #expect(session.editor.string == markdown)
        let storage = try #require(session.editor.textStorage)
        #expect(storage.string == markdown)
        #expect(session.textStorage.string == markdown)
    }

    @Test func openMissingFileFailsWithoutCrashing() {
        let missing = uniqueTempMarkdownURL()
        let session = DocumentSession()
        #expect(throws: DocumentSessionError.self) {
            try session.open(url: missing)
        }
        #expect(session.editor.string.isEmpty)
    }

    @Test func openUnreadableUTF8FailsWithoutCrashing() throws {
        let url = uniqueTempMarkdownURL()
        try Data([0xFF, 0xFE, 0x00]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        #expect(throws: DocumentSessionError.self) {
            try session.open(url: url)
        }
        #expect(session.editor.string.isEmpty)
    }
}

import Combine
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

    @Test func saveWritesFullUTF8EvenWhenFoldedAndDirtyTracksEdits() throws {
        let url = uniqueTempMarkdownURL()
        let markdown = """
        ## Heading two

        Hidden body.

        ```swift
        let answer = 42
        ```

        ## After
        """
        try Data(markdown.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)
        #expect(!session.isDirty)

        let heading = try #require(session.editor.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        session.editor.foldStore.toggle(heading.id)
        session.editor.applyFolds()
        session.editor.ensureLayout()

        session.editor.insertTextAtCaret("EDIT ")
        #expect(session.isDirty)

        try session.save()
        #expect(!session.isDirty)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == session.editor.string)
        #expect(onDisk.hasPrefix("EDIT "))
        #expect(onDisk.contains("Hidden body."))
        #expect(DocumentSave.writeUTF8(from: session.textStorage) == Data(onDisk.utf8))
    }

    @Test func revertReloadsDiskAndClearsDirty() throws {
        let url = uniqueTempMarkdownURL()
        let original = "# Keep me\n"
        try Data(original.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)
        session.editor.insertTextAtCaret("NOPE ")
        #expect(session.isDirty)

        try session.revert()
        #expect(session.editor.string == original)
        #expect(!session.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test func autosaveWritesIfDirty() throws {
        let url = uniqueTempMarkdownURL()
        try Data("# Start\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)
        session.editor.insertTextAtCaret("X")
        try session.autosave()
        #expect(!session.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == session.editor.string)
    }

    @Test func failedSecondOpenKeepsPreviousFileAndAllowsSave() throws {
        let first = uniqueTempMarkdownURL()
        let original = "# First\n"
        try Data(original.utf8).write(to: first)
        defer { try? FileManager.default.removeItem(at: first) }

        let session = DocumentSession()
        try session.open(url: first)
        session.editor.insertTextAtCaret("KEEP ")

        let missing = uniqueTempMarkdownURL()
        #expect(throws: DocumentSessionError.self) {
            try session.open(url: missing)
        }

        #expect(session.fileURL == first)
        #expect(session.editor.string.hasPrefix("KEEP "))
        try session.save()
        #expect(try String(contentsOf: first, encoding: .utf8) == session.editor.string)
    }

    @Test func insertTextAtCaretPublishesDirty() throws {
        let url = uniqueTempMarkdownURL()
        try Data("# Clean\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)
        #expect(!session.isDirty)

        var published = false
        let cancellable = session.objectWillChange.sink { published = true }
        session.editor.insertTextAtCaret("DIRTY ")
        #expect(session.isDirty)
        #expect(published)
        _ = cancellable
    }
}

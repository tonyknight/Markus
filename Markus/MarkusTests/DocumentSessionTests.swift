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

    private func isolatedFoldDefaults() -> UserDefaults {
        let suite = "markus.folds.session.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
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

    @Test func openTimeRestoreRepairsPersistedFoldsAgainstTheFreshlyLoadedIndex() throws {
        let url = uniqueTempMarkdownURL()
        let original = """
        ## Drop

        Body drop.

        ## Keep

        Body keep.
        """
        try Data(original.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let defaults = isolatedFoldDefaults()
        let firstStore = FoldStore(persistence: FoldPersistence(defaults: defaults))
        let firstSession = DocumentSession(editor: FoldingTextView(foldStore: firstStore))
        try firstSession.open(url: url)

        let keepOriginal = try #require(firstSession.editor.blocks.first { $0.id.kind == .heading && $0.id.startLine != 1 })
        firstSession.editor.foldStore.toggle(keepOriginal.id)
        firstSession.editor.applyFolds()
        firstSession.editor.ensureLayout()
        #expect(firstSession.editor.foldStore.isFolded(keepOriginal.id))

        // Edit the file on disk (as if edited elsewhere before the app
        // reopens it), removing "## Drop" and shifting "## Keep" up.
        let edited = """
        ## Keep

        Body keep.
        """
        try Data(edited.utf8).write(to: url)

        // A brand-new session sharing only the same persistence suite and
        // file URL — simulating relaunch, then reopening the same file.
        let secondStore = FoldStore(persistence: FoldPersistence(defaults: defaults))
        let secondSession = DocumentSession(editor: FoldingTextView(foldStore: secondStore))
        try secondSession.open(url: url)

        let keepRepaired = try #require(secondSession.editor.blocks.first { $0.id.kind == .heading && $0.id.anchor == keepOriginal.id.anchor })
        #expect(keepRepaired.id.startLine != keepOriginal.id.startLine)
        #expect(secondSession.editor.foldStore.isFolded(keepRepaired.id))
    }
}

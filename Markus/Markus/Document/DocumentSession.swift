import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum DocumentSessionError: Error, Equatable {
    case missingFile
    case unreadable
    case noFile
}

@MainActor
final class DocumentSession: ObservableObject {
    let editor: FoldingTextView
    private(set) var fileURL: URL?
    private var lastSavedText = ""

    var textStorage: NSTextStorage {
        editor.documentTextStorage
    }

    var isDirty: Bool {
        editor.string != lastSavedText
    }

    init(editor: FoldingTextView = FoldingTextView()) {
        self.editor = editor
    }

    func open(url: URL) throws {
        let markdown = try readUTF8(from: url)
        fileURL = url
        lastSavedText = markdown
        editor.loadMarkdown(markdown)
        objectWillChange.send()
    }

    func save() throws {
        guard let fileURL else { throw DocumentSessionError.noFile }
        let data = DocumentSave.writeUTF8(from: textStorage)
        try data.write(to: fileURL, options: .atomic)
        lastSavedText = editor.string
        objectWillChange.send()
    }

    func revert() throws {
        guard let fileURL else { throw DocumentSessionError.noFile }
        try open(url: fileURL)
    }

    func autosave() throws {
        guard isDirty else { return }
        try save()
    }

    private func readUTF8(from url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentSessionError.missingFile
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentSessionError.unreadable
        }
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw DocumentSessionError.unreadable
        }
        return markdown
    }
}

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
}

@MainActor
final class DocumentSession: ObservableObject {
    let editor: FoldingTextView
    private(set) var fileURL: URL?

    var textStorage: NSTextStorage {
        editor.documentTextStorage
    }

    init(editor: FoldingTextView = FoldingTextView()) {
        self.editor = editor
    }

    func open(url: URL) throws {
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
        fileURL = url
        editor.loadMarkdown(markdown)
    }
}

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
    private let kindPins: KindPin
    private(set) var fileURL: URL?
    /// Untitled documents stay markdown until New-of-type or `setKind`.
    /// Open uses pin ?? UTI/extension.
    private(set) var kind: DocumentKind = .markdown
    private var lastSavedText = ""
    private var scopedURL: URL?
    private var isAccessing = false

    var textStorage: NSTextStorage {
        editor.documentTextStorage
    }

    var isDirty: Bool {
        editor.string != lastSavedText
    }

    var mode: EditorMode {
        editor.mode
    }

    /// Outline rows from the active `SyntaxProfile` (v1.4 data hook).
    var outlineItems: [OutlineItem] {
        editor.session.analysis.outlineRows
    }

    /// Parse diagnostics from the active `SyntaxProfile` (v1.4 data hook).
    var diagnostics: [ParseDiagnostic] {
        editor.session.analysis.diagnostics
    }

    init(editor: FoldingTextView = FoldingTextView(), kindPins: KindPin = KindPin()) {
        self.editor = editor
        self.kindPins = kindPins
        self.editor.onTextDidChange = { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func open(url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let markdown = try readUTF8(from: url)
            releaseAccess()
            isAccessing = accessing
            scopedURL = url
            fileURL = url
            applyKind(kindPins.resolvedKind(for: url))
            lastSavedText = markdown
            editor.loadMarkdown(markdown)
            editor.restoreFolds(for: url)
            objectWillChange.send()
        } catch {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    private func releaseAccess() {
        if isAccessing, let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        scopedURL = nil
    }

    func save() throws {
        guard let fileURL else { throw DocumentSessionError.noFile }
        let data = DocumentSave.writeUTF8(from: textStorage)
        try data.write(to: fileURL, options: .atomic)
        markSaved(at: fileURL)
    }

    func markSaved(at url: URL? = nil) {
        if let url {
            fileURL = url
        }
        lastSavedText = editor.string
        objectWillChange.send()
    }

    func markLoaded(_ markdown: String, kind: DocumentKind = .markdown) {
        lastSavedText = markdown
        applyKind(kind)
        objectWillChange.send()
    }

    /// Kind must be set on the editor *before* `loadMarkdown` / reparse
    /// so the active profile builds the matching foldables.
    private func applyKind(_ kind: DocumentKind) {
        self.kind = kind
        editor.session.documentKind = kind
        if kind != .markdown, editor.mode != .source {
            editor.setMode(.source)
        }
    }

    /// Session-only kind change. Does not write a pin.
    func setKind(_ kind: DocumentKind) {
        applyKind(kind)
        editor.loadMarkdown(editor.string)
        objectWillChange.send()
    }

    var isKindPinned: Bool {
        guard let fileURL else { return false }
        return kindPins.kind(for: fileURL) != nil
    }

    /// Persist the current kind for this file identity. No-op for untitled.
    func pinKind() {
        guard let fileURL else { return }
        kindPins.set(kind, for: fileURL)
        objectWillChange.send()
    }

    /// Drop the pin so the next open (and this session) follow extension/UTI.
    func unpinKind() {
        guard let fileURL else { return }
        guard kindPins.kind(for: fileURL) != nil else { return }
        kindPins.remove(for: fileURL)
        setKind(DocumentKind.from(url: fileURL))
    }

    func revert() throws {
        guard let fileURL else { throw DocumentSessionError.noFile }
        try open(url: fileURL)
    }

    func autosave() throws {
        guard isDirty else { return }
        try save()
    }

    func setMode(_ mode: EditorMode) {
        editor.setMode(mode)
        objectWillChange.send()
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

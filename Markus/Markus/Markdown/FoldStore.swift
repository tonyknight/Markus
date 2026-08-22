import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum EditorMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case preview
    case source

    var displayName: String {
        switch self {
        case .preview: return "Preview"
        case .source: return "Source"
        }
    }
}

final class FoldStore {
    private(set) var foldedIDs: Set<FoldID> = []
    private let persistence: FoldPersistence
    private var boundURL: URL?

    init(persistence: FoldPersistence = FoldPersistence()) {
        self.persistence = persistence
    }

    /// Binds this store to a file, loading whatever fold set was
    /// persisted for it (empty if none). Every subsequent mutation is
    /// persisted back under this file's key (R16).
    func bind(to url: URL?) {
        boundURL = url
        foldedIDs = url.map(persistence.load(for:)) ?? []
    }

    func toggle(_ id: FoldID) {
        if foldedIDs.contains(id) {
            foldedIDs.remove(id)
        } else {
            foldedIDs.insert(id)
        }
        persist()
    }

    func isFolded(_ id: FoldID) -> Bool {
        foldedIDs.contains(id)
    }

    func foldAll<S: Sequence>(_ ids: S) where S.Element == FoldID {
        foldedIDs.formUnion(ids)
        persist()
    }

    func unfoldAll() {
        foldedIDs.removeAll()
        persist()
    }

    func foldedIDs(for mode: EditorMode) -> Set<FoldID> {
        foldedIDs
    }

    func hiddenByteRanges(in blocks: [Block]) -> [Range<Int>] {
        blocks.compactMap { block in
            guard isFolded(block.id) else { return nil }
            return block.foldExtent
        }
    }

    /// Re-matches every folded `FoldID` against the current block index by
    /// `kind` + `anchor`, replacing stale `startLine`s with the block's
    /// current one. A fold whose anchor no longer matches any block (its
    /// block was deleted) is dropped rather than left dangling (R17).
    /// `kind` is a profile string; v1.2 Markdown `"heading"` / `"fence"`
    /// records still match Markdown profile blocks.
    func repair(against blocks: [Block]) {
        var repaired: Set<FoldID> = []
        for id in foldedIDs {
            if let match = blocks.first(where: { $0.id.kind == id.kind && $0.id.anchor == id.anchor }) {
                repaired.insert(match.id)
            }
        }
        foldedIDs = repaired
        persist()
    }

    private func persist() {
        guard let boundURL else { return }
        persistence.save(foldedIDs, for: boundURL)
    }
}

enum DocumentSave {
    static func writeUTF8(from storage: NSTextStorage) -> Data {
        Data(storage.string.utf8)
    }
}

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum EditorMode: Equatable, Hashable, Sendable {
    case source
    case preview
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

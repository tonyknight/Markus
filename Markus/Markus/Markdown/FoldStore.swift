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

    func toggle(_ id: FoldID) {
        if foldedIDs.contains(id) {
            foldedIDs.remove(id)
        } else {
            foldedIDs.insert(id)
        }
    }

    func isFolded(_ id: FoldID) -> Bool {
        foldedIDs.contains(id)
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
}

enum DocumentSave {
    static func writeUTF8(from storage: NSTextStorage) -> Data {
        Data(storage.string.utf8)
    }
}

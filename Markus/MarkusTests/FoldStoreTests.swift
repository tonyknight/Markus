import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

struct FoldStoreTests {
    private var fixture: String {
        """
        ## Heading two

        A paragraph under the H2.

        ### Nested three

        ```swift
        let answer = 42
        ```

        ## Following two
        """
    }

    @Test func toggleFoldIsSharedAcrossSourceAndPreviewAndSaveKeepsFullUTF8() throws {
        let blocks = BlockIndex.build(markdown: fixture)
        let heading = try #require(blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        let fence = try #require(blocks.first { $0.id.kind == .fence })

        let store = FoldStore()
        #expect(store.foldedIDs.isEmpty)

        store.toggle(heading.id)
        store.toggle(fence.id)

        #expect(store.isFolded(heading.id))
        #expect(store.isFolded(fence.id))
        #expect(store.foldedIDs == Set([heading.id, fence.id]))

        let sourceMode = EditorMode.source
        let previewMode = EditorMode.preview
        #expect(store.foldedIDs(for: sourceMode) == store.foldedIDs(for: previewMode))

        store.toggle(heading.id)
        #expect(!store.isFolded(heading.id))
        #expect(store.isFolded(fence.id))

        let storage = NSTextStorage(string: fixture)
        let foldedBytes = store.hiddenByteRanges(in: blocks)
        #expect(!foldedBytes.isEmpty)
        #expect(foldedBytes.reduce(0) { $0 + $1.count } < fixture.utf8.count)

        let saved = DocumentSave.writeUTF8(from: storage)
        #expect(saved == Data(fixture.utf8))
        #expect(String(data: saved, encoding: .utf8) == fixture)
        #expect(storage.string == fixture)
    }

    @Test func foldAllFoldsEveryFoldableBlockAndUnfoldAllClearsAll() throws {
        let blocks = BlockIndex.build(markdown: fixture)
        let foldableIDs = blocks.compactMap { $0.foldExtent != nil ? $0.id : nil }
        // Fixture has two headings and one fence, all foldable.
        #expect(foldableIDs.count == 3)

        let store = FoldStore()
        #expect(store.foldedIDs.isEmpty)

        store.foldAll(foldableIDs)
        for id in foldableIDs {
            #expect(store.isFolded(id))
        }
        #expect(store.foldedIDs == Set(foldableIDs))

        store.unfoldAll()
        #expect(store.foldedIDs.isEmpty)
        for id in foldableIDs {
            #expect(!store.isFolded(id))
        }
    }
}

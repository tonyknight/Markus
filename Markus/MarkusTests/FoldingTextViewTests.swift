import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct FoldingTextViewTests {
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

    @Test func hidesFoldedRangesInBothModesWithoutShrinkingBufferOrBreakingUndo() throws {
        let view = FoldingTextView()
        view.loadMarkdown(fixture)

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        let fence = try #require(view.blocks.first { $0.id.kind == .fence })

        view.ensureLayout()
        let unfoldedHeight = view.layoutHeight
        #expect(unfoldedHeight > 0)

        view.foldStore.toggle(heading.id)
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        let foldedPreviewHeight = view.layoutHeight
        #expect(view.hiddenRangeCount > 0)
        #expect(foldedPreviewHeight < unfoldedHeight)
        #expect(view.string == fixture)
        let storage = try #require(view.textStorage)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(fixture.utf8))

        view.setMode(.source)
        view.ensureLayout()
        let foldedSourceHeight = view.layoutHeight
        #expect(foldedSourceHeight < unfoldedHeight)
        #expect(view.foldStore.isFolded(heading.id))
        #expect(view.foldStore.isFolded(fence.id))
        #expect(view.string == fixture)

        view.setMode(.preview)
        view.ensureLayout()
        #expect(view.foldStore.isFolded(heading.id))
        #expect(view.layoutHeight < unfoldedHeight)

        view.setMode(.source)
        view.ensureLayout()
        let beforeEdit = view.string
        view.insertTextAtCaret("X")
        #expect(view.string != beforeEdit)
        let undid = view.undoLastChange()
        #expect(undid)
        #expect(view.string == beforeEdit)
    }
}

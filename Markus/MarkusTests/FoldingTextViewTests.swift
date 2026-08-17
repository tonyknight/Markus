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

    @Test func hidesFoldedRangesViaLayoutFragmentsWithoutShrinkingBufferOrBreakingUndo() throws {
        let view = FoldingTextView()
        #if os(macOS)
        #expect(!(view is NSTextView))
        #else
        #expect(!(view is UITextView))
        #endif
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()
        let unfoldedSourceHeight = view.layoutHeight
        #expect(unfoldedSourceHeight > 0)

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        let fence = try #require(view.blocks.first { $0.id.kind == .fence })

        view.foldStore.toggle(heading.id)
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.layoutHeight < unfoldedSourceHeight)
        #expect(view.string == fixture)
        let storage = try #require(view.textStorage)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(fixture.utf8))
        #expect(!usesCollapsedParagraphStyles(storage))

        view.setMode(.preview)
        view.ensureLayout()
        #expect(view.foldStore.isFolded(heading.id))
        #expect(view.foldStore.isFolded(fence.id))
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.string == fixture)

        view.setMode(.source)
        view.ensureLayout()
        #expect(view.layoutHeight < unfoldedSourceHeight)

        view.foldStore.toggle(heading.id)
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(!view.foldStore.isFolded(heading.id))
        #expect(!view.foldStore.isFolded(fence.id))
        #expect(abs(view.layoutHeight - unfoldedSourceHeight) < 1)

        let beforeEdit = view.string
        view.insertTextAtCaret("X")
        #expect(view.string != beforeEdit)
        let undid = view.undoLastChange()
        #expect(undid)
        #expect(view.string == beforeEdit)
    }

    @Test func foldAllCollapsesEveryFoldableBlockAndUnfoldAllRestoresLayoutHeight() throws {
        let view = FoldingTextView()
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()
        let unfoldedHeight = view.layoutHeight
        #expect(unfoldedHeight > 0)

        let foldableBlocks = view.blocks.filter { $0.foldExtent != nil }
        // Fixture has two headings and one fence, all foldable.
        #expect(foldableBlocks.count == 3)
        for block in foldableBlocks {
            #expect(!view.foldStore.isFolded(block.id))
        }

        view.foldAll()
        for block in foldableBlocks {
            #expect(view.foldStore.isFolded(block.id))
        }
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.layoutHeight < unfoldedHeight)
        #expect(view.string == fixture)
        let storage = try #require(view.textStorage)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(fixture.utf8))

        view.unfoldAll()
        for block in foldableBlocks {
            #expect(!view.foldStore.isFolded(block.id))
        }
        #expect(abs(view.layoutHeight - unfoldedHeight) < 1)
    }

    private func usesCollapsedParagraphStyles(_ storage: NSTextStorage) -> Bool {
        var found = false
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            guard let style = value as? NSParagraphStyle else { return }
            if style.maximumLineHeight > 0, style.maximumLineHeight <= 0.02 {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

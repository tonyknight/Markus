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

    @Test func foldedFenceShowsOpeningLinePlusPlaceholderInsteadOfAnEmptyGap() throws {
        let view = FoldingTextView()
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let fence = try #require(view.blocks.first { $0.id.kind == .fence })
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()

        // Only the closing fence line collapses to zero height; the body's
        // first line becomes a visible, non-zero-height placeholder instead
        // of also collapsing to zero — so the fence no longer vanishes into
        // an empty gap after its opening line (R15). Before this task, both
        // the body line and the closing fence line collapsed, so this count
        // was 2.
        #expect(view.collapsedFragmentCount == 1)

        var placeholders: [FoldingTextLayoutFragment] = []
        view.textLayoutManager.enumerateTextLayoutFragments(
            from: view.textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            if let folding = fragment as? FoldingTextLayoutFragment, folding.isPlaceholder {
                placeholders.append(folding)
            }
            return true
        }
        #expect(placeholders.count == 1)
        let placeholder = try #require(placeholders.first)
        #expect(!placeholder.isCollapsed)
        #expect(placeholder.layoutFragmentFrame.height > 0)

        // The buffer itself is untouched (N3): the real body text is still
        // there in full, byte for byte — only the drawn placeholder glyph
        // stands in for it, nothing is rewritten or hidden via near-zero
        // paragraph styles.
        #expect(view.string == fixture)
        let storage = try #require(view.textStorage)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(fixture.utf8))
    }

    @Test func foldSurvivesAnEditElsewhereInTheDocumentViaBlockIndexRebuildRepair() throws {
        let twoBlockFixture = """
        ## Block B

        Body B marker HERE.

        ## Block A

        Body A.
        """
        let view = FoldingTextView()
        view.loadMarkdown(twoBlockFixture)
        view.setMode(.source)
        view.ensureLayout()

        // Fold block A, then edit inside block B — elsewhere in the
        // document — in a way that grows block B's body and pushes block
        // A's startLine down. This exercises the real rebuild path
        // (syncBlocksFromStorage), not a hand-constructed block list.
        let blockAOriginal = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine != 1 })
        view.foldStore.toggle(blockAOriginal.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.foldStore.isFolded(blockAOriginal.id))

        let storage = try #require(view.textStorage)
        let match = try #require(FindReplace.search("HERE", in: storage))
        let replaced = FindReplace.replace(match, with: "HERE\nExtra line one.\nExtra line two.", in: storage)
        #expect(replaced)

        view.syncBlocksFromStorage()
        view.ensureLayout()

        let blockARepaired = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.anchor == blockAOriginal.id.anchor })
        #expect(blockARepaired.id.startLine != blockAOriginal.id.startLine)
        #expect(view.foldStore.isFolded(blockARepaired.id))
        #expect(!view.foldStore.foldedIDs.contains(blockAOriginal.id))
    }

    // MARK: - Viewport exposure (minimap T02)

    @Test func currentVisiblePackedRectExposesTheEditorsVisibleRegion() {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 300), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        // No enclosing NSScrollView in this headless test, so the editor
        // falls back to reporting its own bounds as the visible region —
        // the same fallback `scrollPackedYOnScreen` already relies on.
        let visible = view.currentVisiblePackedRect()
        #expect(visible.size == view.bounds.size)
        #expect(visible.origin == .zero)
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

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

        // Fold the ancestor heading alone first: its foldExtent spans
        // to the next same-or-shallower heading, so it already covers
        // the nested H3 and the fence beneath it.
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()
        let heightWithOnlyHeadingFolded = view.layoutHeight
        #expect(heightWithOnlyHeadingFolded > 0)
        #expect(heightWithOnlyHeadingFolded < unfoldedSourceHeight)

        // Also folding the nested fence must not change what's visible
        // — the heading already hides it — an exact equality check,
        // not just "something collapsed": a regression here previously
        // let content between the fence's end and the heading's end
        // leak back into view when both were folded together (fold
        // extents nest, so the hidden-range cache held overlapping
        // ranges; see the ticket's Notes).
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.layoutHeight < unfoldedSourceHeight)
        #expect(view.layoutHeight == heightWithOnlyHeadingFolded)
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

        // Baseline: folding just the top-level heading alone already
        // hides everything nested inside it (the H3 and the fence) —
        // the exact height Fold All's nested/overlapping fold extents
        // must match.
        let topHeading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.foldStore.toggle(topHeading.id)
        view.applyFolds()
        view.ensureLayout()
        let heightWithOnlyTopHeadingFolded = view.layoutHeight
        view.foldStore.toggle(topHeading.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(abs(view.layoutHeight - unfoldedHeight) < 1)

        view.foldAll()
        for block in foldableBlocks {
            #expect(view.foldStore.isFolded(block.id))
        }
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.layoutHeight < unfoldedHeight)
        // Fold All simultaneously folds the top heading, the nested H3,
        // and the doubly-nested fence — exactly the overlapping-fold-
        // extent shape that previously let content leak back into view
        // (see the ticket's Notes). The result must be identical to
        // folding the top heading alone.
        #expect(view.layoutHeight == heightWithOnlyTopHeadingFolded)
        #expect(view.string == fixture)
        let storage = try #require(view.textStorage)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(fixture.utf8))

        view.unfoldAll()
        for block in foldableBlocks {
            #expect(!view.foldStore.isFolded(block.id))
        }
        #expect(abs(view.layoutHeight - unfoldedHeight) < 1)
    }

    // MARK: - Overlapping/nested fold extents (T05 review finding, P4)

    /// A heading's `foldExtent` spans to the next same-or-shallower
    /// heading, so it necessarily contains any nested sub-heading's or
    /// fenced code block's own `foldExtent`. Folding an outer block and
    /// something nested inside it at the same time — this fixture folds
    /// the fence, then its ancestor heading — produces overlapping
    /// hidden ranges. `FoldingSession`'s binary-search hidden-range
    /// lookup (added for P1/P4 performance on this ticket) originally
    /// assumed hidden ranges never overlap; when they do, it can pick
    /// the *inner* (nested) range as the search candidate and wrongly
    /// classify a fragment past the inner range's end — but still
    /// inside the outer range — as `.visible`. This test's trailing
    /// paragraph sits exactly there.
    @Test func foldingANestedFenceAndItsAncestorHeadingTogetherHidesEverythingInBetween() throws {
        let nestedFixture = """
        ## Heading two

        ### Nested three

        ```swift
        let answer = 42
        ```

        Trailing paragraph under heading two, after the fence closes.

        ## Following two
        """
        let view = FoldingTextView()
        view.loadMarkdown(nestedFixture)
        view.setMode(.source)
        view.ensureLayout()

        let ancestorHeading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        let fence = try #require(view.blocks.first { $0.id.kind == .fence })

        // Baseline: folding only the ancestor heading already hides the
        // nested heading, the fence, and the trailing paragraph — all
        // of it lies inside the ancestor's foldExtent.
        view.foldStore.toggle(ancestorHeading.id)
        view.applyFolds()
        view.ensureLayout()
        let unfoldedHeight = { () -> CGFloat in
            let probe = FoldingTextView()
            probe.loadMarkdown(nestedFixture)
            probe.setMode(.source)
            probe.ensureLayout()
            return probe.layoutHeight
        }()
        let heightWithOnlyAncestorFolded = view.layoutHeight
        #expect(heightWithOnlyAncestorFolded > 0)
        #expect(heightWithOnlyAncestorFolded < unfoldedHeight)

        // Also folding the nested fence must not reveal anything the
        // ancestor was already hiding — exact equality, not a weaker
        // "something collapsed" check.
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.layoutHeight == heightWithOnlyAncestorFolded)
        #expect(view.string == nestedFixture)

        // Folding in the opposite order (fence first, then its
        // ancestor) must land at the same height — this is the exact
        // sequence a user produces with two ordinary chevron clicks.
        view.foldStore.toggle(ancestorHeading.id)
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(!view.foldStore.isFolded(ancestorHeading.id))
        #expect(!view.foldStore.isFolded(fence.id))
        view.foldStore.toggle(fence.id)
        view.applyFolds()
        view.ensureLayout()
        view.foldStore.toggle(ancestorHeading.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.layoutHeight == heightWithOnlyAncestorFolded)
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

    // MARK: - Refresh on document change, not just SwiftUI re-render (minimap T05)

    @Test func toggleFoldFoldAllAndUnfoldAllNotifyOnTextDidChange() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        var changeCount = 0
        view.onTextDidChange = { changeCount += 1 }

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.toggleFold(atSourceLine: heading.id.startLine)
        #expect(changeCount == 1)

        view.foldAll()
        #expect(changeCount == 2)

        view.unfoldAll()
        #expect(changeCount == 3)
    }

    @Test func setModeAndSetZoomScaleNotifyOnTextDidChange() {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.ensureLayout()

        var changeCount = 0
        view.onTextDidChange = { changeCount += 1 }

        view.setMode(.preview)
        #expect(changeCount == 1)

        view.setZoomScale(1.2)
        #expect(changeCount == 2)
    }

    // MARK: - Viewport-only drawing (T01, P1)

    @Test func drawFragmentsEnumerationIsBoundedByViewportNotDocumentSize() {
        let visibleRect = CGRect(x: 0, y: 0, width: 480, height: 800)
        let context = makeBitmapContext()

        let smallView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        smallView.loadMarkdown(headingsFixture(count: 5))
        smallView.setMode(.source)
        smallView.ensureLayout()
        smallView.session.drawFragments(in: context, visibleRect: visibleRect)
        let smallCount = smallView.session.fragmentsEnumeratedLastDraw

        let largeView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        largeView.loadMarkdown(headingsFixture(count: 5000))
        largeView.setMode(.source)
        largeView.ensureLayout()
        largeView.session.drawFragments(in: context, visibleRect: visibleRect)
        let largeCount = largeView.session.fragmentsEnumeratedLastDraw

        #expect(smallCount > 0)
        #expect(largeCount > 0)
        // A document 1,000x larger must not enumerate proportionally more
        // fragments when only a small viewport is visible — bounded by
        // the viewport, not the document (P1).
        #expect(largeCount < smallCount * 20)
        #expect(largeCount < 200)
    }

    private func headingsFixture(count: Int) -> String {
        (1...count).map { "## Heading \($0)" }.joined(separator: "\n\n")
    }

    private func makeBitmapContext() -> CGContext {
        CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
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

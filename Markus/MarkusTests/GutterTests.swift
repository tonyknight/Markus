import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct GutterTests {
    private var fixture: String {
        """
        ## Heading two

        A paragraph under the H2.

        ```swift
        let answer = 42
        ```
        """
    }

    @Test func macGutterShowsSourceNumbersAndFoldChevronsInBothModes() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.preview)
        view.ensureLayout()

        #expect(view.gutterWidth > 0)
        #expect(view.textContainer.size.width <= view.bounds.width - view.gutterWidth + 0.5)
        // Preview is block-anchored (R13): one number at each rendered
        // block's true start — heading@1, paragraph@3, and the fence as
        // a single block at its opening delimiter (5), not a second
        // number at its closing delimiter (7). Blank lines (2, 4) and
        // the fence's own body line (6, raw pass-through text, not a
        // substituted block) get no number either. Chevrons still mark
        // both foldable block starts (1 and 5) — even though the
        // fence's own opening line is itself invisible markup (R10, so
        // never its own `SourceLineMap.Entry`) and must resolve its
        // drawn/clickable position to the fence's first visible line
        // instead.
        #expect(view.gutterLineNumbers() == [1, 3, 5])
        #expect(view.gutterLineNumbers() != view.visibleSourceLines)
        #expect(view.foldableSourceLines().contains(1))
        #expect(view.foldableSourceLines().contains(5))

        view.setMode(.source)
        view.ensureLayout()
        #expect(!view.gutterLineNumbers().isEmpty)
        #expect(view.gutterLineNumbers() == view.visibleSourceLines)
        #expect(view.foldableSourceLines().contains(1))

        #if os(macOS)
        view.showLineNumbers = false
        view.ensureLayout()
        #expect(view.showLineNumbers)
        #expect(!view.gutterLineNumbers().isEmpty)
        #endif

        let before = view.collapsedFragmentCount
        view.toggleFold(atSourceLine: 1)
        #expect(view.collapsedFragmentCount > before)
        let storage = try #require(view.textStorage)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(fixture.utf8))
        #expect(view.string == fixture)
    }

    @Test func previewFenceChevronResolvesToItsFirstVisibleLineAndStaysClickable() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.preview)
        view.ensureLayout()

        // The fence's own opening delimiter (line 5) is markup-only and
        // hidden by design (R10, "Markdown punctuation not displayed as
        // literal text") — it never gets its own `SourceLineMap.Entry`.
        #expect(view.y(forSourceLine: 5) == nil)
        let fenceBlock = try #require(view.blocks.first { $0.id.kind == .fence })
        #expect(fenceBlock.id.startLine == 5)

        // The chevron must still resolve to *some* visible position (the
        // fence's first genuinely visible line, its body at 6) and stay
        // clickable there — a chevron the user can see but can never
        // click would be worse than drawing none at all.
        let bodyY = try #require(view.y(forSourceLine: 6))
        let bodyHeight = try #require(view.sourceLineHeight(forSourceLine: 6))

        #expect(!view.foldStore.isFolded(fenceBlock.id))
        let toggled = view.handleGutterClick(at: CGPoint(x: 4, y: bodyY + bodyHeight / 2))
        #expect(toggled)
        #expect(view.foldStore.isFolded(fenceBlock.id))
    }

    // MARK: - T02: confirm PreviewElement.lines' anchor actually drives the gutter

    @Test func previewMultiPhysicalLineParagraphAnchorsToItsFirstLineAtTheBlocksActualRenderedPosition() throws {
        let multiLine = """
            ## Heading two

            Alpha bravo.
            Charlie delta.
            Echo foxtrot.
            """
        let singleLine = """
            ## Heading two

            Alpha bravo. Charlie delta. Echo foxtrot.
            """

        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(multiLine)
        view.setMode(.preview)
        view.ensureLayout()

        // Ticket 08's PreviewElement.lines already carries the source
        // anchor for a substituted paragraph — this proves the gutter
        // (T01) actually consumes it, not new anchor-carrying plumbing.
        // The 3-physical-line paragraph (source lines 3-5) is one
        // ParsedPreviewBlock anchored at its first physical line only.
        #expect(view.session.previewBlockAnchorLines.contains(3))
        #expect(!view.session.previewBlockAnchorLines.contains(4))
        #expect(!view.session.previewBlockAnchorLines.contains(5))

        // Exactly one number for the whole block, not one per physical
        // source line (R13's actual premise).
        let numbers = view.gutterLineNumbers()
        #expect(numbers.filter { (3...5).contains($0) } == [3])

        // Lines 4 and 5 have no visual position of their own at all —
        // the whole block rendered on line 3's single fragment ("multi-
        // line elements render their whole content on the anchor line",
        // `PreviewElement`'s own doc comment).
        #expect(view.y(forSourceLine: 4) == nil)
        #expect(view.y(forSourceLine: 5) == nil)

        // Geometric proof, not just absence: the anchor's entry occupies
        // the same height a genuinely single-physical-line rendering of
        // the identical text does — the number is drawn at the position
        // the block's one real rendered fragment occupies, not a
        // three-line-tall span or three separate slots collapsed into
        // one report.
        let multiHeight = try #require(view.sourceLineHeight(forSourceLine: 3))

        let referenceView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        referenceView.loadMarkdown(singleLine)
        referenceView.setMode(.preview)
        referenceView.ensureLayout()
        let singleHeight = try #require(referenceView.sourceLineHeight(forSourceLine: 3))

        #expect(abs(multiHeight - singleHeight) < 0.5)
    }

    @Test func slimFoldRailIsNarrowerThanNumberedGutter() {
        #expect(GutterMetrics.width(showLineNumbers: false) < GutterMetrics.width(showLineNumbers: true))
        #expect(GutterMetrics.width(showLineNumbers: false) == GutterMetrics.chevronWidth)
    }

    // MARK: - Gutter computes visible-range entries only (T02, P2)

    @Test func gutterSourceLineMapScansLinesBoundedByViewportNotDocumentSize() {
        let visibleRect = CGRect(x: 0, y: 0, width: 480, height: 800)

        let smallView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        smallView.loadMarkdown(headingsFixture(count: 5))
        smallView.setMode(.source)
        smallView.ensureLayout()
        _ = smallView.session.sourceLineMap(boundedBy: visibleRect)
        let smallCount = smallView.session.sourceLinesScannedLastGutterCompute

        let largeView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        largeView.loadMarkdown(headingsFixture(count: 5000))
        largeView.setMode(.source)
        largeView.ensureLayout()
        _ = largeView.session.sourceLineMap(boundedBy: visibleRect)
        let largeCount = largeView.session.sourceLinesScannedLastGutterCompute

        #expect(smallCount > 0)
        #expect(largeCount > 0)
        // A document 1,000x larger must not scan proportionally more
        // source lines when only a small viewport is visible — never
        // O(lines) over the whole document, let alone O(lines ×
        // fragments) (P2).
        #expect(largeCount < smallCount * 20)
        #expect(largeCount < 200)
    }

    private func headingsFixture(count: Int) -> String {
        (1...count).map { "## Heading \($0)" }.joined(separator: "\n\n")
    }

    #if os(iOS)
    @Test func iosHidingLineNumbersLeavesSlimRailThatStillFolds() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.preview)
        view.showLineNumbers = true
        view.ensureLayout()
        let numberedWidth = view.gutterWidth
        #expect(!view.gutterLineNumbers().isEmpty)
        #expect(view.foldableSourceLines().contains(1))

        view.showLineNumbers = false
        view.ensureLayout()
        #expect(!view.showLineNumbers)
        #expect(view.gutterLineNumbers().isEmpty)
        #expect(view.gutterWidth < numberedWidth)
        #expect(view.gutterWidth == GutterMetrics.chevronWidth)
        #expect(view.foldableSourceLines().contains(1))

        let before = view.collapsedFragmentCount
        view.toggleFold(atSourceLine: 1)
        #expect(view.collapsedFragmentCount > before)

        view.setMode(.source)
        view.ensureLayout()
        #expect(!view.showLineNumbers)
        #expect(view.gutterLineNumbers().isEmpty)
        #expect(view.foldableSourceLines().contains(1))

        view.showLineNumbers = true
        view.ensureLayout()
        #expect(view.showLineNumbers)
        #expect(view.gutterLineNumbers() == view.visibleSourceLines)
    }
    #endif
}

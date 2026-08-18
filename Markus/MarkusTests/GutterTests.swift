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
        #expect(!view.gutterLineNumbers().isEmpty)
        #expect(view.gutterLineNumbers() == view.visibleSourceLines)
        #expect(view.foldableSourceLines().contains(1))

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

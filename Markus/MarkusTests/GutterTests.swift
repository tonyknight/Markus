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
}

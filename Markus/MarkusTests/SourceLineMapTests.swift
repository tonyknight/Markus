import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct SourceLineMapTests {
    /// Heading, wrapped paragraph, fence — source numbers, not wrap rows.
    private var fixture: String {
        """
        ## Heading two

        \(String(repeating: "word ", count: 60))

        ```swift
        let answer = 42
        ```
        """
    }

    @Test func sourceLineMapUsesPackedYOmitsFoldedLinesAndDoesNotInventWrapNumbers() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 160, height: 900), foldStore: FoldStore())
        view.textContainer.size = CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        view.loadMarkdown(fixture)
        view.setMode(.preview)
        view.ensureLayout()

        let sourceLineCount = SourceMap(markdown: fixture).lineStarts.count
        let visible = view.visibleSourceLines
        #expect(visible.count == sourceLineCount)
        #expect(visible == Array(1...sourceLineCount))

        let line1Y = try #require(view.y(forSourceLine: 1))
        let laterLine = visible.last { $0 > 1 } ?? sourceLineCount
        let laterY = try #require(view.y(forSourceLine: laterLine))
        #expect(line1Y < laterY)

        #expect(view.sourceLine(atY: line1Y) == 1)

        let paragraphLine = 3
        let paragraphY = try #require(view.y(forSourceLine: paragraphLine))
        let paragraphHeight = try #require(view.sourceLineHeight(forSourceLine: paragraphLine))
        #expect(paragraphHeight > 20)
        #expect(view.sourceLine(atY: paragraphY + paragraphHeight * 0.7) == paragraphLine)

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()

        #expect(view.y(forSourceLine: 1) != nil)
        #expect(view.visibleSourceLines.contains(1))
        #expect(view.y(forSourceLine: paragraphLine) == nil)
        #expect(!view.visibleSourceLines.contains(paragraphLine))
        #expect(view.sourceLine(atY: try #require(view.y(forSourceLine: 1))) == 1)
    }
}

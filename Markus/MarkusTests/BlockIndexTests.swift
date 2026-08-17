import Foundation
import Testing
@testable import Markus

struct BlockIndexTests {
    /// H2, paragraph, nested H3, fence, following H2 — as specified on T01.
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

    @Test func indexReportsATXHeadingAndFenceByteAndLineRangesWithFoldExtents() {
        let index = BlockIndex.build(markdown: fixture)

        let headings = index.filter { block in
            if case .heading = block.kind { return true }
            return false
        }
        let fences = index.filter { $0.kind == .fencedCode }

        #expect(headings.count == 3)
        #expect(fences.count == 1)

        let h2 = headings[0]
        let h3 = headings[1]
        let following = headings[2]
        let fence = fences[0]

        #expect(h2.kind == .heading(level: 2))
        #expect(h2.lines == 1..<2)
        #expect(h2.bytes == utf8Range(ofLine: 1))
        #expect(h2.foldExtent == utf8Range(fromEndOfLine: 1, toStartOfLine: 11))
        #expect(h2.id.kind == .heading)
        #expect(h2.id.startLine == 1)
        #expect(h2.id.anchor == FoldAnchor.digest("## Heading two"))

        #expect(h3.kind == .heading(level: 3))
        #expect(h3.lines == 5..<6)
        #expect(h3.bytes == utf8Range(ofLine: 5))
        #expect(h3.foldExtent == utf8Range(fromEndOfLine: 5, toStartOfLine: 11))
        #expect(h3.id.kind == .heading)
        #expect(h3.id.startLine == 5)
        #expect(h3.id.anchor == FoldAnchor.digest("### Nested three"))

        #expect(following.kind == .heading(level: 2))
        #expect(following.lines == 11..<12)
        #expect(following.bytes == utf8Range(ofLine: 11))
        #expect(following.foldExtent == nil)

        #expect(fence.kind == .fencedCode)
        #expect(fence.lines == 7..<10)
        #expect(fence.bytes == utf8Range(fromStartOfLine: 7, toEndOfLine: 9))
        #expect(fence.foldExtent == utf8Range(fromEndOfLine: 7, toEndOfLine: 9))
        #expect(fence.id.kind == .fence)
        #expect(fence.id.startLine == 7)
        #expect(fence.id.anchor == FoldAnchor.digest("```swift"))

        let opener = Data(fixture.utf8)[utf8Range(ofLine: 7)]
        #expect(String(data: opener, encoding: .utf8) == "```swift\n")
        #expect(fence.bytes.lowerBound == utf8Range(ofLine: 7).lowerBound)
        #expect(fence.foldExtent?.lowerBound == utf8Range(ofLine: 8).lowerBound)
    }

    @Test func anchorDigestIsStableForIdenticalOpeningLinesAndDiffersForDifferentOnes() {
        let a = FoldAnchor.digest("## Same heading")
        let b = FoldAnchor.digest("## Same heading")
        let c = FoldAnchor.digest("## Different heading")

        #expect(a == b)
        #expect(a != c)
    }

    @Test func blocksWithIdenticalOpeningLineTextShareTheSameAnchorButDifferentStartLines() {
        let markdown = """
        ## Repeat

        First body.

        ## Repeat

        Second body.
        """
        let index = BlockIndex.build(markdown: markdown)
        let headings = index.filter { block in
            if case .heading = block.kind { return true }
            return false
        }

        #expect(headings.count == 2)
        #expect(headings[0].id.anchor == headings[1].id.anchor)
        #expect(headings[0].id.startLine != headings[1].id.startLine)
    }

    private func utf8Range(ofLine line: Int) -> Range<Int> {
        utf8Range(fromStartOfLine: line, toEndOfLine: line)
    }

    private func utf8Range(fromEndOfLine line: Int, toStartOfLine endLine: Int) -> Range<Int> {
        utf8Range(fromStartOfLine: line, toEndOfLine: line).upperBound
            ..< utf8Range(fromStartOfLine: endLine, toEndOfLine: endLine).lowerBound
    }

    private func utf8Range(fromEndOfLine line: Int, toEndOfLine endLine: Int) -> Range<Int> {
        utf8Range(fromStartOfLine: line, toEndOfLine: line).upperBound
            ..< utf8Range(fromStartOfLine: endLine, toEndOfLine: endLine).upperBound
    }

    private func utf8Range(fromStartOfLine start: Int, toEndOfLine end: Int) -> Range<Int> {
        let data = Data(fixture.utf8)
        var lineStarts: [Int] = [0]
        for (index, byte) in data.enumerated() where byte == UInt8(ascii: "\n") {
            lineStarts.append(index + 1)
        }
        let lower = lineStarts[start - 1]
        let upper: Int
        if end < lineStarts.count {
            upper = lineStarts[end]
        } else {
            upper = data.count
        }
        return lower..<upper
    }
}

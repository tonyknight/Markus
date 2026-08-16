import Foundation
import Testing
@testable import Markus

struct MarkdownParserTests {
    @Test func parseReportsHeadingLevel2AndFencedCode() {
        let fixture = """
        ## Heading

        ```swift
        let answer = 42
        ```
        """

        let blocks = MarkdownParser().parse(fixture)

        let heading = blocks.first { block in
            if case .heading = block.kind { return true }
            return false
        }
        let fence = blocks.first { block in
            if case .fencedCode = block.kind { return true }
            return false
        }

        #expect(heading?.kind == .heading(level: 2))
        #expect(fence?.kind == .fencedCode)
    }

    @Test func previewSpansCoverGFMFixtureAndIgnoreMathMermaid() throws {
        let markdown = GFMPreviewFixture.markdown
        let parser = MarkdownParser()

        let blocks = parser.parse(markdown)
        #expect(blocks.contains { if case .heading(let level) = $0.kind { return level == 1 } else { return false } })
        #expect(blocks.filter { $0.kind == .fencedCode }.count == 2)

        let spans = parser.previewSpans(markdown)
        func first(_ kind: MarkdownSpanKind) -> MarkdownSpan? {
            spans.first { $0.kind == kind }
        }
        func utf8Slice(_ bytes: Range<Int>) -> String {
            let data = Data(markdown.utf8)
            return String(data: data.subdata(in: bytes), encoding: .utf8) ?? ""
        }
        func utf8Bytes(of substring: String) -> Range<Int>? {
            guard let range = markdown.range(of: substring) else { return nil }
            let start = markdown.utf8.distance(from: markdown.startIndex, to: range.lowerBound)
            let end = markdown.utf8.distance(from: markdown.startIndex, to: range.upperBound)
            return start..<end
        }

        let heading = try #require(first(.heading(level: 1)))
        let table = try #require(first(.table))
        let task = try #require(first(.taskListItem))
        let strike = try #require(first(.strikethrough))
        let footnote = try #require(first(.footnote))
        let fence = try #require(first(.fencedCode))
        let link = try #require(first(.link))
        let inlineCode = try #require(first(.inlineCode))

        #expect(heading.bytes.count > 0)
        #expect(table.bytes.count > 0)
        #expect(task.bytes.count > 0)
        #expect(strike.bytes.count > 0)
        #expect(footnote.bytes.count > 0)
        #expect(fence.bytes.count > 0)
        #expect(link.bytes.count > 0)
        #expect(inlineCode.bytes.count > 0)

        #expect(utf8Slice(strike.bytes).contains("gone"))
        #expect(utf8Slice(inlineCode.bytes).contains("inline"))
        #expect(utf8Slice(link.bytes).contains("link"))
        #expect(utf8Slice(table.bytes).contains("Col"))
        #expect(utf8Slice(task.bytes).contains("[ ]") || utf8Slice(task.bytes).contains("unchecked"))

        if let dollar = utf8Bytes(of: "$x$") {
            let covering = spans.filter { $0.bytes.overlaps(dollar) }
            #expect(!covering.contains { $0.kind == .inlineCode })
            #expect(!covering.contains { $0.kind == .fencedCode })
        }

        if let mermaidStart = utf8Bytes(of: "```mermaid")?.lowerBound {
            let mermaidSpans = spans.filter { $0.bytes.contains(mermaidStart) && $0.kind == .fencedCode }
            #expect(!mermaidSpans.isEmpty)
        }
    }
}

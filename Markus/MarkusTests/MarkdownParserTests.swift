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
}

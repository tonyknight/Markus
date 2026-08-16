import cmark_gfm
import cmark_gfm_extensions

/// Thin wrapper around cmark-gfm with GFM extensions enabled.
nonisolated struct MarkdownParser: Sendable {
    func parse(_ markdown: String) -> [MarkdownBlock] {
        let byteCount = markdown.utf8.count
        let sourceMap = SourceMap(markdown: markdown)
        return markdown.withCString { cString in
            parseUTF8(cString, byteCount: byteCount, sourceMap: sourceMap)
        }
    }

    private func parseUTF8(
        _ utf8: UnsafePointer<CChar>,
        byteCount: Int,
        sourceMap: SourceMap
    ) -> [MarkdownBlock] {
        cmark_gfm_core_extensions_ensure_registered()

        let options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
        guard let parser = cmark_parser_new(options) else { return [] }
        defer { cmark_parser_free(parser) }

        for name in ["table", "tasklist", "strikethrough", "autolink", "tagfilter", "footnotes"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, utf8, byteCount)
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }

        guard let iterator = cmark_iter_new(document) else { return [] }
        defer { cmark_iter_free(iterator) }

        var blocks: [MarkdownBlock] = []
        while true {
            let event = cmark_iter_next(iterator)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER else { continue }

            let node = cmark_iter_get_node(iterator)
            let type = cmark_node_get_type(node)
            let startLine = Int(cmark_node_get_start_line(node))
            let endLine = Int(cmark_node_get_end_line(node))
            guard startLine > 0, endLine >= startLine else { continue }
            let lines = sourceMap.lineRange(startLine: startLine, endLine: endLine)
            let bytes = sourceMap.byteRange(startLine: startLine, endLine: endLine)

            if type == CMARK_NODE_HEADING {
                let level = Int(cmark_node_get_heading_level(node))
                blocks.append(MarkdownBlock(kind: .heading(level: level), bytes: bytes, lines: lines))
            } else if type == CMARK_NODE_CODE_BLOCK {
                var fenceLength: Int32 = 0
                var fenceOffset: Int32 = 0
                var fenceCharacter: CChar = 0
                let isFenced = cmark_node_get_fenced(
                    node,
                    &fenceLength,
                    &fenceOffset,
                    &fenceCharacter
                ) != 0
                if isFenced {
                    blocks.append(MarkdownBlock(kind: .fencedCode, bytes: bytes, lines: lines))
                } else {
                    blocks.append(MarkdownBlock(kind: .other, bytes: bytes, lines: lines))
                }
            }
        }
        return blocks
    }
}

nonisolated enum MarkdownBlockKind: Equatable, Sendable {
    case heading(level: Int)
    case fencedCode
    case other
}

nonisolated struct MarkdownBlock: Equatable, Sendable {
    var kind: MarkdownBlockKind
    var bytes: Range<Int>
    var lines: Range<Int>
}

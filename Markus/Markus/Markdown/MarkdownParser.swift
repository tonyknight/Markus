import cmark_gfm
import cmark_gfm_extensions

/// Thin wrapper around cmark-gfm with GFM extensions enabled.
nonisolated struct MarkdownParser: Sendable {
    func parse(_ markdown: String) -> [MarkdownBlock] {
        let byteCount = markdown.utf8.count
        return markdown.withCString { cString in
            parseUTF8(cString, byteCount: byteCount)
        }
    }

    private func parseUTF8(_ utf8: UnsafePointer<CChar>, byteCount: Int) -> [MarkdownBlock] {
        cmark_gfm_core_extensions_ensure_registered()

        let options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES
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
            if type == CMARK_NODE_HEADING {
                let level = Int(cmark_node_get_heading_level(node))
                blocks.append(MarkdownBlock(kind: .heading(level: level)))
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
                    blocks.append(MarkdownBlock(kind: .fencedCode))
                } else {
                    blocks.append(MarkdownBlock(kind: .other))
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
}

import cmark_gfm
import cmark_gfm_extensions

/// Thin wrapper around cmark-gfm with GFM extensions enabled.
nonisolated struct MarkdownParser: Sendable {
    func parse(_ markdown: String) -> [MarkdownBlock] {
        walk(markdown).blocks
    }

    func previewSpans(_ markdown: String) -> [MarkdownSpan] {
        walk(markdown).spans
    }

    private func isFenced(_ node: UnsafeMutablePointer<cmark_node>?) -> Bool {
        var fenceLength: Int32 = 0
        var fenceOffset: Int32 = 0
        var fenceCharacter: CChar = 0
        return cmark_node_get_fenced(node, &fenceLength, &fenceOffset, &fenceCharacter) != 0
    }

    private func sourceByteRange(
        of node: UnsafeMutablePointer<cmark_node>?,
        sourceMap: SourceMap
    ) -> Range<Int>? {
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))
        let startColumn = Int(cmark_node_get_start_column(node))
        let endColumn = Int(cmark_node_get_end_column(node))
        guard startLine > 0, endLine >= startLine else { return nil }
        if startColumn > 0, endColumn > 0 {
            return sourceMap.byteRange(
                startLine: startLine,
                startColumn: startColumn,
                endLine: endLine,
                endColumn: endColumn
            )
        }
        return sourceMap.byteRange(startLine: startLine, endLine: endLine)
    }

    private func walk(_ markdown: String) -> (blocks: [MarkdownBlock], spans: [MarkdownSpan]) {
        let byteCount = markdown.utf8.count
        let sourceMap = SourceMap(markdown: markdown)
        return markdown.withCString { cString in
            cmark_gfm_core_extensions_ensure_registered()

            let options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
            guard let parser = cmark_parser_new(options) else { return ([], []) }
            defer { cmark_parser_free(parser) }

            for name in ["table", "tasklist", "strikethrough", "autolink", "tagfilter", "footnotes"] {
                if let ext = cmark_find_syntax_extension(name) {
                    cmark_parser_attach_syntax_extension(parser, ext)
                }
            }

            cmark_parser_feed(parser, cString, byteCount)
            guard let document = cmark_parser_finish(parser) else { return ([], []) }
            defer { cmark_node_free(document) }

            guard let iterator = cmark_iter_new(document) else { return ([], []) }
            defer { cmark_iter_free(iterator) }

            var blocks: [MarkdownBlock] = []
            var spans: [MarkdownSpan] = []
            while true {
                let event = cmark_iter_next(iterator)
                if event == CMARK_EVENT_DONE { break }
                guard event == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iterator)
                collectBlock(node, sourceMap: sourceMap, into: &blocks)
                collectSpan(node, sourceMap: sourceMap, into: &spans)
            }
            return (blocks, spans)
        }
    }

    private func collectBlock(
        _ node: UnsafeMutablePointer<cmark_node>?,
        sourceMap: SourceMap,
        into blocks: inout [MarkdownBlock]
    ) {
        let type = cmark_node_get_type(node)
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))
        guard startLine > 0, endLine >= startLine else { return }
        let lines = sourceMap.lineRange(startLine: startLine, endLine: endLine)
        let bytes = sourceMap.byteRange(startLine: startLine, endLine: endLine)

        if type == CMARK_NODE_HEADING {
            let level = Int(cmark_node_get_heading_level(node))
            blocks.append(MarkdownBlock(kind: .heading(level: level), bytes: bytes, lines: lines))
        } else if type == CMARK_NODE_CODE_BLOCK, isFenced(node) {
            blocks.append(MarkdownBlock(kind: .fencedCode, bytes: bytes, lines: lines))
        } else if type == CMARK_NODE_CODE_BLOCK {
            blocks.append(MarkdownBlock(kind: .other, bytes: bytes, lines: lines))
        }
    }

    private func collectSpan(
        _ node: UnsafeMutablePointer<cmark_node>?,
        sourceMap: SourceMap,
        into spans: inout [MarkdownSpan]
    ) {
        guard let bytes = sourceByteRange(of: node, sourceMap: sourceMap), !bytes.isEmpty else { return }
        let type = cmark_node_get_type(node)
        let typeName = String(cString: cmark_node_get_type_string(node))

        if type == CMARK_NODE_HEADING {
            let level = Int(cmark_node_get_heading_level(node))
            spans.append(MarkdownSpan(kind: .heading(level: level), bytes: bytes))
        } else if typeName == "table" {
            spans.append(MarkdownSpan(kind: .table, bytes: bytes))
        } else if typeName == "tasklist" {
            spans.append(MarkdownSpan(kind: .taskListItem, bytes: bytes))
        } else if typeName == "strikethrough" {
            spans.append(MarkdownSpan(kind: .strikethrough, bytes: bytes))
        } else if type == CMARK_NODE_FOOTNOTE_DEFINITION || type == CMARK_NODE_FOOTNOTE_REFERENCE {
            spans.append(MarkdownSpan(kind: .footnote, bytes: bytes))
        } else if type == CMARK_NODE_CODE_BLOCK, isFenced(node) {
            spans.append(MarkdownSpan(kind: .fencedCode, bytes: bytes))
        } else if type == CMARK_NODE_LINK {
            spans.append(MarkdownSpan(kind: .link, bytes: bytes))
        } else if type == CMARK_NODE_CODE {
            spans.append(MarkdownSpan(kind: .inlineCode, bytes: bytes))
        }
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

nonisolated enum MarkdownSpanKind: Equatable, Sendable {
    case heading(level: Int)
    case table
    case taskListItem
    case strikethrough
    case footnote
    case fencedCode
    case link
    case inlineCode
}

nonisolated struct MarkdownSpan: Equatable, Sendable {
    var kind: MarkdownSpanKind
    var bytes: Range<Int>
}

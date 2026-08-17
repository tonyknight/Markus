import cmark_gfm
import cmark_gfm_extensions

/// Column alignment for a GFM table column, as parsed from the delimiter row.
nonisolated enum TableColumnAlignment: Equatable, Sendable {
    case none
    case left
    case center
    case right
}

/// A GFM table extracted from the cmark AST: its rows (header first), the
/// per-column alignment, and the table's full source byte range so a later
/// selection over its rendered attachment can resolve back to Markdown.
nonisolated struct ParsedTable: Equatable, Sendable {
    var sourceRange: Range<Int>
    var alignments: [TableColumnAlignment]
    var rows: [[String]]
    var headerRowIndex: Int
}

/// Walks the cmark-gfm AST for `CMARK_NODE_TABLE` nodes and extracts their
/// structure. Separate from `MarkdownParser.previewSpans`, which only reports
/// the table's byte range for attribute-only styling — this produces the
/// cell content and alignment a `TableAttachment` needs to measure and draw
/// a true grid.
nonisolated enum TableParsing: Sendable {
    static func parseTables(in markdown: String) -> [ParsedTable] {
        let byteCount = markdown.utf8.count
        let sourceMap = SourceMap(markdown: markdown)
        return markdown.withCString { cString in
            cmark_gfm_core_extensions_ensure_registered()

            let options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
            guard let parser = cmark_parser_new(options) else { return [] }
            defer { cmark_parser_free(parser) }

            for name in ["table", "tasklist", "strikethrough", "autolink", "tagfilter", "footnotes"] {
                if let ext = cmark_find_syntax_extension(name) {
                    cmark_parser_attach_syntax_extension(parser, ext)
                }
            }

            cmark_parser_feed(parser, cString, byteCount)
            guard let document = cmark_parser_finish(parser) else { return [] }
            defer { cmark_node_free(document) }

            guard let iterator = cmark_iter_new(document) else { return [] }
            defer { cmark_iter_free(iterator) }

            var tables: [ParsedTable] = []
            while true {
                let event = cmark_iter_next(iterator)
                if event == CMARK_EVENT_DONE { break }
                guard event == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iterator)
                guard String(cString: cmark_node_get_type_string(node)) == "table" else { continue }
                if let table = parseTable(node, sourceMap: sourceMap) {
                    tables.append(table)
                }
            }
            return tables
        }
    }

    private static func parseTable(
        _ node: UnsafeMutablePointer<cmark_node>?,
        sourceMap: SourceMap
    ) -> ParsedTable? {
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))
        guard startLine > 0, endLine >= startLine else { return nil }
        let sourceRange = sourceMap.byteRange(startLine: startLine, endLine: endLine)

        let columnCount = Int(cmark_gfm_extensions_get_table_columns(node))
        guard columnCount > 0 else { return nil }

        let alignments: [TableColumnAlignment]
        if let raw = cmark_gfm_extensions_get_table_alignments(node) {
            alignments = (0..<columnCount).map { alignment(from: raw[$0]) }
        } else {
            alignments = Array(repeating: .none, count: columnCount)
        }

        var rows: [[String]] = []
        var headerRowIndex = 0
        var rowNode = cmark_node_first_child(node)
        while let row = rowNode {
            var cells: [String] = []
            var cellNode = cmark_node_first_child(row)
            while let cell = cellNode {
                cells.append(cellText(cell))
                cellNode = cmark_node_next(cell)
            }
            while cells.count < columnCount { cells.append("") }
            if cmark_gfm_extensions_get_table_row_is_header(row) != 0 {
                headerRowIndex = rows.count
            }
            rows.append(cells)
            rowNode = cmark_node_next(row)
        }

        guard !rows.isEmpty else { return nil }
        return ParsedTable(
            sourceRange: sourceRange,
            alignments: alignments,
            rows: rows,
            headerRowIndex: headerRowIndex
        )
    }

    private static func alignment(from raw: UInt8) -> TableColumnAlignment {
        switch raw {
        case UInt8(ascii: "l"): return .left
        case UInt8(ascii: "c"): return .center
        case UInt8(ascii: "r"): return .right
        default: return .none
        }
    }

    /// Concatenates the literal text of a table cell's inline children,
    /// ignoring emphasis/strong/code markup — a plain-text approximation
    /// sufficient for measuring column widths and drawing cell text.
    private static func cellText(_ cell: UnsafeMutablePointer<cmark_node>?) -> String {
        var text = ""
        var child = cmark_node_first_child(cell)
        while let node = child {
            appendLiteralText(node, into: &text)
            child = cmark_node_next(node)
        }
        return text
    }

    private static func appendLiteralText(_ node: UnsafeMutablePointer<cmark_node>?, into text: inout String) {
        if let literal = cmark_node_get_literal(node) {
            text += String(cString: literal)
        }
        var child = cmark_node_first_child(node)
        while let n = child {
            appendLiteralText(n, into: &text)
            child = cmark_node_next(n)
        }
    }
}

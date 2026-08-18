import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// A pure-Swift, cmark-free representation of one inline run inside a
/// `ParsedPreviewBlock`. Produced once per text change by
/// `PreviewStructureCollector` (which does touch cmark); consumed any
/// number of times by `PreviewElementRenderer` (which never does) to
/// bake in the current theme/zoom without re-parsing (P3).
indirect enum PreviewInlineNode: Equatable {
    case text(String)
    case softBreak
    case code(String)
    case emph([PreviewInlineNode])
    case strong([PreviewInlineNode])
    case strikethrough([PreviewInlineNode])
    case link(url: URL?, children: [PreviewInlineNode])
    case image(alt: String)
    /// An unhandled container node (e.g. a raw inline span, a footnote
    /// reference): render its children with no additional styling —
    /// mirrors the pre-refactor `renderInlineNode` default-with-children
    /// fallback exactly.
    case group([PreviewInlineNode])
}

/// Structure-only representation of one Preview-relevant block: which
/// source lines it occupies and what kind of content it is, with no
/// fonts or colors baked in. `PreviewStructureCollector.collect`
/// produces this by walking cmark exactly once per text change;
/// `PreviewElementRenderer.render` turns it into styled
/// `PreviewElement`s any number of times afterward without touching
/// cmark again — the decoupling P3 requires (fold toggle, theme
/// change, zoom step, mode switch, and container resize all only need
/// to re-render, never re-parse).
struct ParsedPreviewBlock: Equatable {
    var lines: Range<Int>
    var indentLevel: Int
    var kind: Kind

    enum Kind: Equatable {
        case heading(level: Int, inline: [PreviewInlineNode])
        case paragraph(inline: [PreviewInlineNode], quoted: Bool)
        case thematicBreak
        /// One markup-only fence delimiter line (opening ``` /~~~, or
        /// the matching close) — collapses to zero height like any
        /// other markup-only substitution.
        case fenceDelimiter
        case listItemLead(marker: String, inline: [PreviewInlineNode])
        case table(ParsedTable)
    }
}

/// Walks the cmark-gfm AST exactly once and produces the structure
/// `PreviewElementRenderer` needs — no fonts, no colors, nothing that
/// depends on `ThemeTokens`/zoom, and nothing that holds a cmark
/// pointer past this call (the tree is freed before `collect` returns,
/// same lifetime discipline the pre-refactor `PreviewElementCollector`
/// already followed).
enum PreviewStructureCollector {
    static func collect(markdown: String) -> [ParsedPreviewBlock] {
        var blocks: [ParsedPreviewBlock] = markdown.withCString { cString in
            cmark_gfm_core_extensions_ensure_registered()
            let options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
            guard let parser = cmark_parser_new(options) else { return [] }
            defer { cmark_parser_free(parser) }
            for name in ["table", "tasklist", "strikethrough", "autolink", "tagfilter", "footnotes"] {
                if let ext = cmark_find_syntax_extension(name) {
                    cmark_parser_attach_syntax_extension(parser, ext)
                }
            }
            cmark_parser_feed(parser, cString, markdown.utf8.count)
            guard let document = cmark_parser_finish(parser) else { return [] }
            defer { cmark_node_free(document) }

            var blocks: [ParsedPreviewBlock] = []
            var child = cmark_node_first_child(document)
            while let node = child {
                collectBlock(node, quoteDepth: 0, listDepth: 0, into: &blocks)
                child = cmark_node_next(node)
            }
            return blocks
        }

        // Tables (ticket 01): a GFM table is a single cmark node
        // spanning several source lines; `TableParsing` already
        // extracts exactly the rows/alignment/source range
        // `TableAttachment` needs. Parsed once here, alongside
        // everything else, not re-invoked on a style-only change.
        let sourceMap = SourceMap(markdown: markdown)
        for table in TableParsing.parseTables(in: markdown) {
            let lines = lineRange(forByteRange: table.sourceRange, sourceMap: sourceMap)
            blocks.append(ParsedPreviewBlock(lines: lines, indentLevel: 0, kind: .table(table)))
        }
        return blocks
    }

    private static func lineRange(forByteRange bytes: Range<Int>, sourceMap: SourceMap) -> Range<Int> {
        let startLine = lineNumber(forByteOffset: bytes.lowerBound, sourceMap: sourceMap)
        let lastByte = max(bytes.lowerBound, bytes.upperBound - 1)
        let endLine = lineNumber(forByteOffset: lastByte, sourceMap: sourceMap)
        return startLine..<(max(startLine, endLine) + 1)
    }

    private static func lineNumber(forByteOffset offset: Int, sourceMap: SourceMap) -> Int {
        var line = 1
        for (index, start) in sourceMap.lineStarts.enumerated() where start <= offset {
            line = index + 1
        }
        return line
    }

    private static func collectBlock(
        _ node: UnsafeMutablePointer<cmark_node>?,
        quoteDepth: Int,
        listDepth: Int,
        into blocks: inout [ParsedPreviewBlock]
    ) {
        guard let node else { return }
        let type = cmark_node_get_type(node)

        if type == CMARK_NODE_BLOCK_QUOTE {
            var child = cmark_node_first_child(node)
            while let n = child {
                collectBlock(n, quoteDepth: quoteDepth + 1, listDepth: listDepth, into: &blocks)
                child = cmark_node_next(n)
            }
            return
        }

        if type == CMARK_NODE_LIST {
            let listType = cmark_node_get_list_type(node)
            let listStart = Int(cmark_node_get_list_start(node))
            var item = cmark_node_first_child(node)
            while let itemNode = item {
                collectListItem(
                    itemNode,
                    listType: listType,
                    listStart: listStart,
                    quoteDepth: quoteDepth,
                    listDepth: listDepth,
                    into: &blocks
                )
                item = cmark_node_next(itemNode)
            }
            return
        }

        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))
        guard startLine > 0, endLine >= startLine else { return }
        let lines = startLine..<(endLine + 1)
        let indentLevel = quoteDepth + listDepth

        if type == CMARK_NODE_HEADING {
            let level = Int(cmark_node_get_heading_level(node))
            let inline = collectInlineChildren(of: node)
            blocks.append(ParsedPreviewBlock(lines: lines, indentLevel: indentLevel, kind: .heading(level: level, inline: inline)))
        } else if type == CMARK_NODE_PARAGRAPH {
            let inline = collectInlineChildren(of: node)
            blocks.append(ParsedPreviewBlock(lines: lines, indentLevel: indentLevel, kind: .paragraph(inline: inline, quoted: quoteDepth > 0)))
        } else if type == CMARK_NODE_THEMATIC_BREAK {
            blocks.append(ParsedPreviewBlock(lines: lines, indentLevel: indentLevel, kind: .thematicBreak))
        } else if type == CMARK_NODE_CODE_BLOCK, isFenced(node) {
            blocks.append(ParsedPreviewBlock(lines: startLine..<(startLine + 1), indentLevel: 0, kind: .fenceDelimiter))
            if endLine > startLine {
                blocks.append(ParsedPreviewBlock(lines: endLine..<(endLine + 1), indentLevel: 0, kind: .fenceDelimiter))
            }
        }
        // Images are handled inline within paragraph/heading/list-item
        // text by `collectInlineNode`'s `CMARK_NODE_IMAGE` case.
    }

    private static func isFenced(_ node: UnsafeMutablePointer<cmark_node>?) -> Bool {
        var fenceLength: Int32 = 0
        var fenceOffset: Int32 = 0
        var fenceCharacter: CChar = 0
        return cmark_node_get_fenced(node, &fenceLength, &fenceOffset, &fenceCharacter) != 0
    }

    private static func collectListItem(
        _ item: UnsafeMutablePointer<cmark_node>,
        listType: cmark_list_type,
        listStart: Int,
        quoteDepth: Int,
        listDepth: Int,
        into blocks: inout [ParsedPreviewBlock]
    ) {
        let typeName = String(cString: cmark_node_get_type_string(item))
        let isTask = typeName == "tasklist"
        let checked = isTask && cmark_gfm_extensions_get_tasklist_item_checked(item)

        let marker: String
        if isTask {
            marker = checked ? "\u{2611} " : "\u{2610} " // ☑ / ☐
        } else if listType == CMARK_ORDERED_LIST {
            let index = Int(cmark_node_get_item_index(item))
            marker = "\(listStart + index). "
        } else {
            marker = "\u{2022} " // •
        }

        var markerConsumed = false
        var child = cmark_node_first_child(item)
        while let n = child {
            let childType = cmark_node_get_type(n)
            if !markerConsumed, childType == CMARK_NODE_PARAGRAPH {
                let startLine = Int(cmark_node_get_start_line(n))
                let endLine = Int(cmark_node_get_end_line(n))
                if startLine > 0, endLine >= startLine {
                    let inline = collectInlineChildren(of: n)
                    blocks.append(ParsedPreviewBlock(
                        lines: startLine..<(endLine + 1),
                        indentLevel: quoteDepth + listDepth,
                        kind: .listItemLead(marker: marker, inline: inline)
                    ))
                }
                markerConsumed = true
            } else if childType == CMARK_NODE_LIST {
                let nestedListType = cmark_node_get_list_type(n)
                let nestedListStart = Int(cmark_node_get_list_start(n))
                var nestedItem = cmark_node_first_child(n)
                while let ni = nestedItem {
                    collectListItem(
                        ni,
                        listType: nestedListType,
                        listStart: nestedListStart,
                        quoteDepth: quoteDepth,
                        listDepth: listDepth + 1,
                        into: &blocks
                    )
                    nestedItem = cmark_node_next(ni)
                }
            } else {
                collectBlock(n, quoteDepth: quoteDepth, listDepth: listDepth, into: &blocks)
            }
            child = cmark_node_next(n)
        }
    }

    // MARK: - Inline structure

    private static func collectInlineChildren(of node: UnsafeMutablePointer<cmark_node>?) -> [PreviewInlineNode] {
        var result: [PreviewInlineNode] = []
        var child = cmark_node_first_child(node)
        while let n = child {
            result.append(collectInlineNode(n))
            child = cmark_node_next(n)
        }
        return result
    }

    private static func collectInlineNode(_ node: UnsafeMutablePointer<cmark_node>) -> PreviewInlineNode {
        let type = cmark_node_get_type(node)

        switch type {
        case CMARK_NODE_TEXT:
            return .text(literalText(node))
        case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
            return .softBreak
        case CMARK_NODE_CODE:
            return .code(literalText(node))
        case CMARK_NODE_EMPH:
            return .emph(collectInlineChildren(of: node))
        case CMARK_NODE_STRONG:
            return .strong(collectInlineChildren(of: node))
        case CMARK_NODE_LINK:
            let url = cmark_node_get_url(node).flatMap { URL(string: String(cString: $0)) }
            return .link(url: url, children: collectInlineChildren(of: node))
        case CMARK_NODE_IMAGE:
            return .image(alt: literalInlineText(of: node))
        default:
            let typeName = String(cString: cmark_node_get_type_string(node))
            if typeName == "strikethrough" {
                return .strikethrough(collectInlineChildren(of: node))
            }
            if cmark_node_first_child(node) != nil {
                return .group(collectInlineChildren(of: node))
            }
            return .text(literalText(node))
        }
    }

    private static func literalText(_ node: UnsafeMutablePointer<cmark_node>?) -> String {
        guard let literal = cmark_node_get_literal(node) else { return "" }
        return String(cString: literal)
    }

    private static func literalInlineText(of node: UnsafeMutablePointer<cmark_node>?) -> String {
        var text = ""
        var child = cmark_node_first_child(node)
        while let n = child {
            text += literalText(n)
            text += literalInlineText(of: n)
            child = cmark_node_next(n)
        }
        return text
    }
}

import Foundation
import cmark_gfm
import cmark_gfm_extensions
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One Preview-substitutable unit: the full run of physical source
/// lines it occupies, and the fully rendered attributed string a reader
/// sees in its place. Multi-line elements render their whole content on
/// the anchor line (`lines.lowerBound`); the remaining lines in `lines`
/// are hidden at layout time via the same zero-height fragment
/// mechanism folding uses (see `FoldingSession.hiddenUTF16Ranges`) —
/// the buffer itself is never touched (N4).
struct PreviewElement {
    var lines: Range<Int>
    private(set) var rendered: NSAttributedString
    /// True for an anchor line whose rendered content is markup-only
    /// (e.g. a fence delimiter, or a heading/paragraph/list item with no
    /// inline content at all — CommonMark permits an empty ATX heading
    /// like `# `) and must collapse to zero height like a continuation
    /// line, rather than laying out as a visible blank line.
    ///
    /// Enforced centrally in `init`, not left to each call site to get
    /// right: `NSTextParagraph` requires non-empty content to correctly
    /// represent a non-empty source range — an empty paragraph over a
    /// non-empty range breaks TextKit 2's layout bookkeeping outright
    /// (`ensureLayout()` never returns; this is exactly what T06's fence
    /// delimiters hit before this guard existed). So construction
    /// silently substitutes a single space and forces `isMarkupOnly`
    /// true whenever the caller-provided `rendered` is zero-length,
    /// regardless of which block/inline kind produced it — no caller
    /// can create a zero-length substitution for a non-empty source
    /// line, by construction.
    private(set) var isMarkupOnly: Bool

    init(lines: Range<Int>, rendered: NSAttributedString, isMarkupOnly: Bool = false) {
        self.lines = lines
        if rendered.length == 0 {
            self.rendered = NSAttributedString(string: " ")
            self.isMarkupOnly = true
        } else {
            self.rendered = rendered
            self.isMarkupOnly = isMarkupOnly
        }
    }
}

/// Heading point sizes by level (H1 largest), scaled by zoom — not a
/// flat 22pt for every level, the v1 mistake R10 corrects.
enum PreviewHeadingScale {
    static func pointSize(level: Int, zoomScale: CGFloat) -> CGFloat {
        let base: CGFloat
        switch level {
        case 1: base = 28
        case 2: base = 24
        case 3: base = 20
        case 4: base = 17
        case 5: base = 15
        default: base = 13
        }
        return base * zoomScale
    }
}

/// Walks the cmark-gfm AST and produces one `PreviewElement` per
/// preview-relevant block. Pure data production — `FoldingSession`
/// hands the result to `PreviewContentStorageDelegate`; nothing here
/// touches `NSTextStorage`, so nothing here can be clobbered by
/// `FoldingSession.applyStyling`'s blind restyle of the buffer.
enum PreviewElementCollector {
    static func collect(markdown: String, tokens: ThemeTokens, zoomScale: CGFloat) -> [PreviewElement] {
        var elements: [PreviewElement] = markdown.withCString { cString in
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

            var elements: [PreviewElement] = []
            var child = cmark_node_first_child(document)
            while let node = child {
                collectBlock(node, tokens: tokens, zoomScale: zoomScale, quoteDepth: 0, listDepth: 0, into: &elements)
                child = cmark_node_next(node)
            }
            return elements
        }

        // Tables are collected separately via TableParsing (ticket 01):
        // a GFM table is a single cmark node spanning several source
        // lines, and TableParsing already extracts exactly the rows,
        // alignment, and source range TableAttachment needs to measure
        // and draw a true grid (R11). The table's other source lines
        // (delimiter row, data rows) collapse via the same
        // continuation-hiding path as any other multi-line element.
        let sourceMap = SourceMap(markdown: markdown)
        let font = PlatformFont.monospaced(size: 14 * zoomScale)
        for table in TableParsing.parseTables(in: markdown) {
            let attachment = TableAttachment(table: table, font: font)
            let lines = lineRange(forByteRange: table.sourceRange, sourceMap: sourceMap)
            elements.append(PreviewElement(lines: lines, rendered: NSAttributedString(attachment: attachment)))
        }
        return elements
    }

    /// Converts a UTF-8 byte range (as produced by cmark sourcepos) to a
    /// 1-based source line range, using the same line numbering as
    /// `SourceMap`/`UTF16LineOffsets`.
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

    /// Dispatches one block-level node. `quoteDepth`/`listDepth` are
    /// 0-based ancestor counts (how many block quotes / how many levels
    /// of list nesting this node sits inside); both drive the
    /// paragraph-style indent applied to the rendered element (R10:
    /// "lists and block quotes shaped ... via paragraph styles").
    private static func collectBlock(
        _ node: UnsafeMutablePointer<cmark_node>?,
        tokens: ThemeTokens,
        zoomScale: CGFloat,
        quoteDepth: Int,
        listDepth: Int,
        into elements: inout [PreviewElement]
    ) {
        guard let node else { return }
        let type = cmark_node_get_type(node)

        if type == CMARK_NODE_BLOCK_QUOTE {
            var child = cmark_node_first_child(node)
            while let n = child {
                collectBlock(n, tokens: tokens, zoomScale: zoomScale, quoteDepth: quoteDepth + 1, listDepth: listDepth, into: &elements)
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
                    tokens: tokens,
                    zoomScale: zoomScale,
                    quoteDepth: quoteDepth,
                    listDepth: listDepth,
                    into: &elements
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
            let font = PlatformFont.heading(size: PreviewHeadingScale.pointSize(level: level, zoomScale: zoomScale))
            let attributed = renderInlineChildren(of: node, font: font, tokens: tokens, defaultColor: tokens.heading)
            elements.append(PreviewElement(lines: lines, rendered: applyIndent(attributed, level: indentLevel)))
        } else if type == CMARK_NODE_PARAGRAPH {
            let font = PlatformFont.body(size: 16 * zoomScale)
            let color = quoteDepth > 0 ? tokens.list : tokens.body
            let attributed = renderInlineChildren(of: node, font: font, tokens: tokens, defaultColor: color)
            elements.append(PreviewElement(lines: lines, rendered: applyIndent(attributed, level: indentLevel)))
        } else if type == CMARK_NODE_THEMATIC_BREAK {
            let attachment = ThematicBreakAttachment(color: tokens.foldMarker)
            let attributed = NSAttributedString(attachment: attachment)
            elements.append(PreviewElement(lines: lines, rendered: applyIndent(attributed, level: indentLevel)))
        } else if type == CMARK_NODE_CODE_BLOCK, isFenced(node) {
            // Only the fence delimiter lines (```/~~~) are markup; the
            // code between them is content, not syntax, so it is left
            // for the default pass-through path (still monospaced/
            // colored by FoldingSession.applyStyling's fallback
            // attributes) rather than substituted here. Each delimiter
            // line gets a markup-only substitution (a single space —
            // never truly empty, see `PreviewElement.isMarkupOnly`),
            // which `PreviewSubstitutionIndex.build` also collapses to
            // zero height (a markup-only line is never meant to occupy
            // space).
            elements.append(PreviewElement(lines: startLine..<(startLine + 1), rendered: NSAttributedString(string: " "), isMarkupOnly: true))
            if endLine > startLine {
                elements.append(PreviewElement(lines: endLine..<(endLine + 1), rendered: NSAttributedString(string: " "), isMarkupOnly: true))
            }
        }
        // Images are handled inline within paragraph/heading/list-item
        // text by `renderInlineNode`'s `CMARK_NODE_IMAGE` case.
    }

    /// Mirrors `MarkdownParser`'s private fenced-code detection: `true`
    /// when `node` is a fenced (``` or ~~~) code block, as opposed to an
    /// indented one (which carries no delimiter markup to hide).
    private static func isFenced(_ node: UnsafeMutablePointer<cmark_node>?) -> Bool {
        var fenceLength: Int32 = 0
        var fenceOffset: Int32 = 0
        var fenceCharacter: CChar = 0
        return cmark_node_get_fenced(node, &fenceLength, &fenceOffset, &fenceCharacter) != 0
    }

    /// One list item: the marker (bullet, ordinal, or task checkbox)
    /// prefixes its own leading paragraph's rendered text; any further
    /// block content in the item (a nested list, a loose item's extra
    /// paragraph) is collected at the appropriate depth without a
    /// marker of its own.
    private static func collectListItem(
        _ item: UnsafeMutablePointer<cmark_node>,
        listType: cmark_list_type,
        listStart: Int,
        tokens: ThemeTokens,
        zoomScale: CGFloat,
        quoteDepth: Int,
        listDepth: Int,
        into elements: inout [PreviewElement]
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

        let font = PlatformFont.body(size: 16 * zoomScale)
        var markerConsumed = false
        var child = cmark_node_first_child(item)
        while let n = child {
            let childType = cmark_node_get_type(n)
            if !markerConsumed, childType == CMARK_NODE_PARAGRAPH {
                let startLine = Int(cmark_node_get_start_line(n))
                let endLine = Int(cmark_node_get_end_line(n))
                if startLine > 0, endLine >= startLine {
                    let inline = renderInlineChildren(of: n, font: font, tokens: tokens, defaultColor: tokens.list)
                    let prefixed = NSMutableAttributedString(
                        string: marker,
                        attributes: [.font: font, .foregroundColor: tokens.list]
                    )
                    prefixed.append(inline)
                    elements.append(PreviewElement(
                        lines: startLine..<(endLine + 1),
                        rendered: applyIndent(prefixed, level: quoteDepth + listDepth)
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
                        tokens: tokens,
                        zoomScale: zoomScale,
                        quoteDepth: quoteDepth,
                        listDepth: listDepth + 1,
                        into: &elements
                    )
                    nestedItem = cmark_node_next(ni)
                }
            } else {
                collectBlock(n, tokens: tokens, zoomScale: zoomScale, quoteDepth: quoteDepth, listDepth: listDepth, into: &elements)
            }
            child = cmark_node_next(n)
        }
    }

    /// Applies a per-nesting-level indent via paragraph style —
    /// "shaping" a list or block quote without ever touching the
    /// buffer or hiding text behind a collapsed style (N3/N4 forbid
    /// exactly that trick in another guise).
    private static func applyIndent(_ attributed: NSAttributedString, level: Int) -> NSAttributedString {
        guard level > 0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat(level) * 20
        style.headIndent = CGFloat(level) * 20
        mutable.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: mutable.length))
        return mutable
    }

    // MARK: - Inline rendering

    /// Concatenates the rendered inline content of `node`'s children:
    /// emphasis/strong become font traits, inline code and
    /// strikethrough get their own attributes, links carry `.link` and
    /// lose their `[]()` syntax, and everything else falls back to
    /// literal text — always via the AST, never a raw-source slice, so
    /// markup punctuation is structurally absent rather than merely
    /// colored over (R10).
    private static func renderInlineChildren(
        of node: UnsafeMutablePointer<cmark_node>?,
        font: PlatformFontType,
        tokens: ThemeTokens,
        defaultColor: PlatformColorType
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var child = cmark_node_first_child(node)
        while let n = child {
            result.append(renderInlineNode(n, font: font, tokens: tokens, defaultColor: defaultColor))
            child = cmark_node_next(n)
        }
        return result
    }

    private static func renderInlineNode(
        _ node: UnsafeMutablePointer<cmark_node>,
        font: PlatformFontType,
        tokens: ThemeTokens,
        defaultColor: PlatformColorType
    ) -> NSAttributedString {
        let type = cmark_node_get_type(node)

        switch type {
        case CMARK_NODE_TEXT:
            return NSAttributedString(string: literalText(node), attributes: [
                .font: font,
                .foregroundColor: defaultColor,
            ])
        case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
            return NSAttributedString(string: " ", attributes: [
                .font: font,
                .foregroundColor: defaultColor,
            ])
        case CMARK_NODE_CODE:
            return NSAttributedString(string: literalText(node), attributes: [
                .font: PlatformFont.monospaced(size: font.pointSize),
                .foregroundColor: tokens.inlineCode,
            ])
        case CMARK_NODE_EMPH:
            return renderInlineChildren(of: node, font: PlatformFont.italic(font), tokens: tokens, defaultColor: defaultColor)
        case CMARK_NODE_STRONG:
            return renderInlineChildren(of: node, font: PlatformFont.bold(font), tokens: tokens, defaultColor: defaultColor)
        case CMARK_NODE_LINK:
            let inner = NSMutableAttributedString(
                attributedString: renderInlineChildren(of: node, font: font, tokens: tokens, defaultColor: tokens.link)
            )
            let fullRange = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            if let rawURL = cmark_node_get_url(node), let url = URL(string: String(cString: rawURL)) {
                inner.addAttribute(.link, value: url, range: fullRange)
            }
            return inner
        case CMARK_NODE_IMAGE:
            // R12: images are not rendered in v1.1 — degrade to
            // readable styled text (an icon plus the alt text, in a
            // distinct italic/muted style) rather than either a real
            // image or the raw `![]()` syntax.
            let alt = literalInlineText(of: node)
            let label = alt.isEmpty ? "Image" : alt
            return NSAttributedString(string: "\u{1F5BC} \(label)", attributes: [
                .font: PlatformFont.italic(font),
                .foregroundColor: tokens.footnote,
            ])
        default:
            let typeName = String(cString: cmark_node_get_type_string(node))
            if typeName == "strikethrough" {
                let inner = NSMutableAttributedString(
                    attributedString: renderInlineChildren(of: node, font: font, tokens: tokens, defaultColor: tokens.strikethrough)
                )
                let fullRange = NSRange(location: 0, length: inner.length)
                inner.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
                return inner
            }
            // Unhandled inline kinds (images handled in T06, footnote
            // references, raw inline HTML, …) fall back to their own
            // rendered children, or literal text for true leaves.
            if cmark_node_first_child(node) != nil {
                return renderInlineChildren(of: node, font: font, tokens: tokens, defaultColor: defaultColor)
            }
            return NSAttributedString(string: literalText(node), attributes: [
                .font: font,
                .foregroundColor: defaultColor,
            ])
        }
    }

    private static func literalText(_ node: UnsafeMutablePointer<cmark_node>?) -> String {
        guard let literal = cmark_node_get_literal(node) else { return "" }
        return String(cString: literal)
    }

    /// Flattens `node`'s descendant text nodes into a plain string,
    /// ignoring formatting — used for an image's alt text, which is
    /// itself inline content (so it can contain emphasis in the source)
    /// but is only ever shown here as the degraded placeholder's label.
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

/// Maps Preview substitution data to the UTF-16 offsets the layout
/// machinery (`NSTextContentStorageDelegate`, `NSTextLayoutManager`)
/// addresses content in. Built fresh from the current buffer, theme,
/// and zoom on every mode/theme/zoom/text change — never cached as
/// attributes on the buffer, which is exactly why
/// `FoldingSession.applyStyling`'s existing blind
/// `setAttributes(_:range:)` cannot clobber it: there is nothing
/// substitution-related on the buffer to clobber.
struct PreviewSubstitutionIndex {
    /// Keyed by the UTF-16 offset of an element's anchor line start.
    private(set) var anchorSubstitutions: [Int: NSAttributedString] = [:]
    /// Full UTF-16 ranges of source lines hidden because they are the
    /// non-anchor continuation of a multi-line element (empty until a
    /// later task introduces multi-line elements: tables, wrapped
    /// paragraphs/quotes, fenced code).
    private(set) var continuationUTF16Ranges: [NSRange] = []

    static func build(markdown: String, tokens: ThemeTokens, zoomScale: CGFloat) -> PreviewSubstitutionIndex {
        let elements = PreviewElementCollector.collect(markdown: markdown, tokens: tokens, zoomScale: zoomScale)
        let lineOffsets = UTF16LineOffsets(markdown: markdown)
        var index = PreviewSubstitutionIndex()
        for element in elements {
            guard let anchorOffset = lineOffsets.utf16Offset(ofLine: element.lines.lowerBound) else { continue }
            index.anchorSubstitutions[anchorOffset] = element.rendered

            if element.isMarkupOnly {
                // A markup-only substitution (e.g. a fence delimiter
                // line) is never meant to occupy space of its own —
                // collapse its own anchor line to zero height too, the
                // same mechanism used for a multi-line element's
                // continuation lines below (N3), not a near-zero font
                // size (N4).
                let end = lineOffsets.utf16EndOffset(ofLine: element.lines.lowerBound)
                if end > anchorOffset {
                    index.continuationUTF16Ranges.append(NSRange(location: anchorOffset, length: end - anchorOffset))
                }
            }

            guard element.lines.count > 1 else { continue }
            let lastLine = element.lines.upperBound - 1
            let continuationStartLine = element.lines.lowerBound + 1
            if let start = lineOffsets.utf16Offset(ofLine: continuationStartLine) {
                let end = lineOffsets.utf16EndOffset(ofLine: lastLine)
                if end > start {
                    index.continuationUTF16Ranges.append(NSRange(location: start, length: end - start))
                }
            }
        }
        return index
    }

    func substitution(atUTF16Offset offset: Int) -> NSAttributedString? {
        anchorSubstitutions[offset]
    }
}

/// UTF-16 analogue of `SourceMap`'s byte-based line starts: needed
/// because `NSTextContentStorageDelegate` and `NSTextLayoutManager`
/// address content in UTF-16 offsets, while `SourceMap`/cmark address
/// it in UTF-8 bytes. Line numbering (1-based, nth line by preceding
/// `\n` count) matches `SourceMap` exactly.
struct UTF16LineOffsets {
    private let starts: [Int]
    private let length: Int

    init(markdown: String) {
        let units = markdown.utf16
        length = units.count
        var offsets = [0]
        var offset = 0
        for unit in units {
            offset += 1
            if unit == 0x0A {
                offsets.append(offset)
            }
        }
        starts = offsets
    }

    /// `line` is 1-based, matching `SourceMap`/cmark line numbering.
    func utf16Offset(ofLine line: Int) -> Int? {
        guard line >= 1, line <= starts.count else { return nil }
        return starts[line - 1]
    }

    func utf16EndOffset(ofLine line: Int) -> Int {
        if line < starts.count { return starts[line] }
        return length
    }

    /// Binary search for the 1-based line containing UTF-16 `offset` —
    /// O(log lines), never a linear scan. Used to bound a viewport-only
    /// computation (e.g. gutter entries) to the handful of lines a
    /// visible fragment actually spans, without ever converting through
    /// byte offsets or scanning every line (P2).
    func lineNumber(atUTF16Offset offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= offset {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result + 1
    }
}

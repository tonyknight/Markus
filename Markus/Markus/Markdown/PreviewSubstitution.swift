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
    var rendered: NSAttributedString
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
        markdown.withCString { cString in
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
                collectBlock(node, tokens: tokens, zoomScale: zoomScale, into: &elements)
                child = cmark_node_next(node)
            }
            return elements
        }
    }

    private static func collectBlock(
        _ node: UnsafeMutablePointer<cmark_node>?,
        tokens: ThemeTokens,
        zoomScale: CGFloat,
        into elements: inout [PreviewElement]
    ) {
        guard let node else { return }
        let type = cmark_node_get_type(node)
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))
        guard startLine > 0, endLine >= startLine else { return }
        let lines = startLine..<(endLine + 1)

        if type == CMARK_NODE_HEADING {
            let level = Int(cmark_node_get_heading_level(node))
            let text = plainInlineText(of: node)
            let attributed = NSAttributedString(string: text, attributes: [
                .font: PlatformFont.heading(size: PreviewHeadingScale.pointSize(level: level, zoomScale: zoomScale)),
                .foregroundColor: tokens.heading,
            ])
            elements.append(PreviewElement(lines: lines, rendered: attributed))
        }
        // Paragraphs, lists, block quotes, thematic breaks, tables,
        // fenced code, and images are added by later tasks (T02–T06).
        // Until then this block kind is simply not substituted — the
        // default raw text lays out unchanged, same as Source mode.
    }

    private static func plainInlineText(of node: UnsafeMutablePointer<cmark_node>?) -> String {
        var text = ""
        var child = cmark_node_first_child(node)
        while let n = child {
            appendLiteral(n, into: &text)
            child = cmark_node_next(n)
        }
        return text
    }

    private static func appendLiteral(_ node: UnsafeMutablePointer<cmark_node>?, into text: inout String) {
        if let literal = cmark_node_get_literal(node) {
            text += String(cString: literal)
        }
        var child = cmark_node_first_child(node)
        while let n = child {
            appendLiteral(n, into: &text)
            child = cmark_node_next(n)
        }
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
}

import Foundation
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

/// Turns cmark-free `ParsedPreviewBlock`s (produced once per text
/// change by `PreviewStructureCollector`) into styled `PreviewElement`s
/// — the exact same font/color logic the pre-refactor
/// `PreviewElementCollector` applied while it still walked cmark
/// directly, just switching over `ParsedPreviewBlock`/
/// `PreviewInlineNode` instead. Pure Swift, no cmark, safe to call on
/// every fold toggle/theme change/zoom step/mode switch/resize without
/// re-parsing (P3).
enum PreviewElementRenderer {
    static func render(_ blocks: [ParsedPreviewBlock], tokens: ThemeTokens, zoomScale: CGFloat) -> [PreviewElement] {
        blocks.map { block in
            switch block.kind {
            case .heading(let level, let inline):
                let font = PlatformFont.heading(size: PreviewHeadingScale.pointSize(level: level, zoomScale: zoomScale))
                let attributed = renderInline(
                    inline,
                    font: font,
                    tokens: tokens,
                    defaultColor: tokens.headingColor(level: level)
                )
                return PreviewElement(lines: block.lines, rendered: applyIndent(attributed, level: block.indentLevel))
            case .paragraph(let inline, let quoted):
                let font = PlatformFont.body(size: 16 * zoomScale)
                let color = quoted ? tokens.list : tokens.body
                let attributed = renderInline(inline, font: font, tokens: tokens, defaultColor: color)
                return PreviewElement(lines: block.lines, rendered: applyIndent(attributed, level: block.indentLevel))
            case .thematicBreak:
                let attachment = ThematicBreakAttachment(color: tokens.foldMarker)
                let attributed = NSAttributedString(attachment: attachment)
                return PreviewElement(lines: block.lines, rendered: applyIndent(attributed, level: block.indentLevel))
            case .fenceDelimiter:
                // Only the fence delimiter lines (```/~~~) are markup;
                // the code between them is content, not syntax, so it
                // is left for the default pass-through path (still
                // monospaced/colored by FoldingSession.applyStyling's
                // fallback attributes) rather than substituted here. A
                // single space — never truly empty, see
                // `PreviewElement.isMarkupOnly` — which
                // `PreviewSubstitutionIndex.build` collapses to zero
                // height (a markup-only line is never meant to occupy
                // space).
                return PreviewElement(lines: block.lines, rendered: NSAttributedString(string: " "), isMarkupOnly: true)
            case .listItemLead(let marker, let inline):
                let font = PlatformFont.body(size: 16 * zoomScale)
                let inlineAttr = renderInline(inline, font: font, tokens: tokens, defaultColor: tokens.list)
                let prefixed = NSMutableAttributedString(
                    string: marker,
                    attributes: [.font: font, .foregroundColor: tokens.list]
                )
                prefixed.append(inlineAttr)
                return PreviewElement(lines: block.lines, rendered: applyIndent(prefixed, level: block.indentLevel))
            case .table(let table):
                let font = PlatformFont.monospaced(size: 14 * zoomScale)
                let attachment = TableAttachment(table: table, font: font)
                return PreviewElement(lines: block.lines, rendered: NSAttributedString(attachment: attachment))
            }
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

    /// Concatenates the rendered inline content of `nodes`: emphasis/
    /// strong become font traits *and* their own token colors, inline
    /// code and strikethrough get their own attributes, links carry
    /// `.link` and lose their `[]()` syntax, and everything else falls
    /// back to literal text — always via the parsed structure, never a
    /// raw-source slice, so markup punctuation is structurally absent
    /// rather than merely colored over (R10).
    private static func renderInline(
        _ nodes: [PreviewInlineNode],
        font: PlatformFontType,
        tokens: ThemeTokens,
        defaultColor: PlatformColorType,
        emphasis: InlineEmphasis = .none
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for node in nodes {
            result.append(renderInlineNode(
                node,
                font: font,
                tokens: tokens,
                defaultColor: defaultColor,
                emphasis: emphasis
            ))
        }
        return result
    }

    private static func renderInlineNode(
        _ node: PreviewInlineNode,
        font: PlatformFontType,
        tokens: ThemeTokens,
        defaultColor: PlatformColorType,
        emphasis: InlineEmphasis
    ) -> NSAttributedString {
        switch node {
        case .text(let string):
            return NSAttributedString(string: string, attributes: [
                .font: font,
                .foregroundColor: defaultColor,
            ])
        case .softBreak:
            return NSAttributedString(string: " ", attributes: [
                .font: font,
                .foregroundColor: defaultColor,
            ])
        case .code(let string):
            return NSAttributedString(string: string, attributes: [
                .font: PlatformFont.monospaced(size: font.pointSize),
                .foregroundColor: tokens.inlineCode,
            ])
        case .emph(let children):
            let next = emphasis.applyingItalic
            return renderInline(
                children,
                font: PlatformFont.italic(font),
                tokens: tokens,
                defaultColor: next.color(tokens: tokens),
                emphasis: next
            )
        case .strong(let children):
            let next = emphasis.applyingBold
            return renderInline(
                children,
                font: PlatformFont.bold(font),
                tokens: tokens,
                defaultColor: next.color(tokens: tokens),
                emphasis: next
            )
        case .link(let url, let children):
            let inner = NSMutableAttributedString(
                attributedString: renderInline(
                    children,
                    font: font,
                    tokens: tokens,
                    defaultColor: tokens.link,
                    emphasis: emphasis
                )
            )
            let fullRange = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            if let url {
                inner.addAttribute(.link, value: url, range: fullRange)
            }
            return inner
        case .image(let alt):
            // R12: images are not rendered in v1.1 — degrade to
            // readable styled text (an icon plus the alt text, in a
            // distinct italic/muted style) rather than either a real
            // image or the raw `![]()` syntax.
            let label = alt.isEmpty ? "Image" : alt
            return NSAttributedString(string: "\u{1F5BC} \(label)", attributes: [
                .font: PlatformFont.italic(font),
                .foregroundColor: tokens.footnote,
            ])
        case .strikethrough(let children):
            let inner = NSMutableAttributedString(
                attributedString: renderInline(
                    children,
                    font: font,
                    tokens: tokens,
                    defaultColor: tokens.strikethrough,
                    emphasis: emphasis
                )
            )
            let fullRange = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            return inner
        case .group(let children):
            // Unhandled container kinds (footnote references, raw
            // inline HTML, …) fall back to their own rendered children
            // with no additional styling.
            return renderInline(
                children,
                font: font,
                tokens: tokens,
                defaultColor: defaultColor,
                emphasis: emphasis
            )
        }
    }
}

/// Nested emphasis for Preview substitution. Font traits still come
/// from `PlatformFont.italic` / `.bold`; these cases only pick color.
private enum InlineEmphasis {
    case none
    case italic
    case bold
    case boldItalic

    var applyingItalic: InlineEmphasis {
        switch self {
        case .none, .italic: .italic
        case .bold, .boldItalic: .boldItalic
        }
    }

    var applyingBold: InlineEmphasis {
        switch self {
        case .none, .bold: .bold
        case .italic, .boldItalic: .boldItalic
        }
    }

    func color(tokens: ThemeTokens) -> PlatformColorType {
        switch self {
        case .none: tokens.body
        case .italic: tokens.italic
        case .bold: tokens.bold
        case .boldItalic: tokens.boldItalic
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

    /// Convenience for callers that don't need the parse/render split
    /// (existing tests, one-shot callers): parses `markdown` once and
    /// renders it immediately. `FoldingSession` does not use this
    /// overload — it caches `[ParsedPreviewBlock]` across style-only
    /// changes and calls `build(markdown:elements:)` directly, which is
    /// what actually makes fold/theme/zoom/mode/resize parse-free (P3).
    static func build(markdown: String, tokens: ThemeTokens, zoomScale: CGFloat) -> PreviewSubstitutionIndex {
        let elements = PreviewElementRenderer.render(
            PreviewStructureCollector.collect(markdown: markdown),
            tokens: tokens,
            zoomScale: zoomScale
        )
        return build(markdown: markdown, elements: elements)
    }

    /// The parse-free path: `elements` were already rendered from a
    /// cached `[ParsedPreviewBlock]` (or from any other source) —
    /// nothing here touches cmark.
    static func build(markdown: String, elements: [PreviewElement]) -> PreviewSubstitutionIndex {
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

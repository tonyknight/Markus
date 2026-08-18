import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    static let markdownSpanKind = NSAttributedString.Key("Markus.markdownSpanKind")
}

enum MarkdownPreviewRenderer {
    static func apply(
        spans: [MarkdownSpan],
        to textStorage: NSTextStorage,
        tokens: ThemeTokens,
        zoomScale: CGFloat = 1
    ) {
        let markdown = textStorage.string
        let scale = max(0.5, min(zoomScale, 3))
        // Build on a scratch NSMutableAttributedString and swap it in
        // once, rather than calling textStorage.addAttributes(_:range:)
        // once per span on the live NSTextStorage — the latter measured
        // as pathologically slow at scale, separately from the byte-
        // offset conversion fix below.
        let mutable = NSMutableAttributedString(attributedString: textStorage)
        // Convert every span's byte range to an NSRange in one batched,
        // single-pass walk over `markdown` (P4) — calling
        // `UTF8NSRange.nsRange(utf8Bytes:in:)` once per span each
        // re-walks the string from its start, which made styling a
        // document with thousands of spans effectively quadratic in
        // document size. See `UTF8NSRange.nsRanges` and the ticket's
        // Notes for the measurement that found this.
        let nsRanges = UTF8NSRange.nsRanges(utf8Bytes: spans.map(\.bytes), in: markdown)
        for (span, nsRange) in zip(spans, nsRanges) {
            guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .markdownSpanKind: span.kind,
            ]
            switch span.kind {
            case .heading:
                attributes[.font] = PlatformFont.heading(size: 22 * scale)
                attributes[.foregroundColor] = tokens.heading
            case .table:
                attributes[.foregroundColor] = tokens.table
            case .taskListItem:
                attributes[.foregroundColor] = tokens.list
            case .strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.foregroundColor] = tokens.strikethrough
            case .footnote:
                attributes[.foregroundColor] = tokens.footnote
            case .fencedCode:
                attributes[.font] = PlatformFont.monospaced(size: 13 * scale)
                attributes[.foregroundColor] = tokens.fence
            case .link:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.foregroundColor] = tokens.link
            case .inlineCode:
                attributes[.font] = PlatformFont.monospaced(size: 13 * scale)
                attributes[.foregroundColor] = tokens.inlineCode
            }
            mutable.addAttributes(attributes, range: nsRange)
        }
        textStorage.setAttributedString(mutable)
    }
}

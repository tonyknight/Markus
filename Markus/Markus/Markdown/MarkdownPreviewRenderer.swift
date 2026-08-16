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
        for span in spans {
            let nsRange = UTF8NSRange.nsRange(utf8Bytes: span.bytes, in: markdown)
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
            textStorage.addAttributes(attributes, range: nsRange)
        }
    }
}

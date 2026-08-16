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
    static func apply(spans: [MarkdownSpan], to textStorage: NSTextStorage) {
        let markdown = textStorage.string
        for span in spans {
            let nsRange = UTF8NSRange.nsRange(utf8Bytes: span.bytes, in: markdown)
            guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .markdownSpanKind: span.kind,
            ]
            switch span.kind {
            case .heading:
                attributes[.font] = PlatformFont.heading(size: 22)
                attributes[.foregroundColor] = PlatformColor.label
            case .table:
                attributes[.foregroundColor] = PlatformColor.label
            case .taskListItem:
                attributes[.foregroundColor] = PlatformColor.label
            case .strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.foregroundColor] = PlatformColor.label
            case .footnote:
                attributes[.foregroundColor] = PlatformColor.label
            case .fencedCode:
                attributes[.font] = PlatformFont.monospaced(size: 13)
                attributes[.foregroundColor] = PlatformColor.label
            case .link:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.foregroundColor] = PlatformColor.label
            case .inlineCode:
                attributes[.font] = PlatformFont.monospaced(size: 13)
                attributes[.foregroundColor] = PlatformColor.label
            }
            textStorage.addAttributes(attributes, range: nsRange)
        }
    }
}

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ThemeTokens: Equatable {
    var background: PlatformColorType
    var body: PlatformColorType
    var h1: PlatformColorType
    var h2: PlatformColorType
    var h3: PlatformColorType
    var h4: PlatformColorType
    var h5: PlatformColorType
    var h6: PlatformColorType
    var bold: PlatformColorType
    var italic: PlatformColorType
    var boldItalic: PlatformColorType
    var link: PlatformColorType
    var inlineCode: PlatformColorType
    var fence: PlatformColorType
    var list: PlatformColorType
    var foldMarker: PlatformColorType
    var table: PlatformColorType
    var strikethrough: PlatformColorType
    var footnote: PlatformColorType
    /// Chrome color for GitHub-style alerts. Ticket 07 binds this; Preview
    /// does not paint callouts yet.
    var callout: PlatformColorType

    static var `default`: ThemeTokens {
        NamedThemeCatalog.tokens(for: .nord, variant: .light)
    }

    /// ATX / setext level 1…6. Out-of-range levels clamp to H1 or H6.
    func headingColor(level: Int) -> PlatformColorType {
        switch level {
        case ...1: h1
        case 2: h2
        case 3: h3
        case 4: h4
        case 5: h5
        default: h6
        }
    }

    static func == (lhs: ThemeTokens, rhs: ThemeTokens) -> Bool {
        lhs.background.isEqual(rhs.background)
            && lhs.body.isEqual(rhs.body)
            && lhs.h1.isEqual(rhs.h1)
            && lhs.h2.isEqual(rhs.h2)
            && lhs.h3.isEqual(rhs.h3)
            && lhs.h4.isEqual(rhs.h4)
            && lhs.h5.isEqual(rhs.h5)
            && lhs.h6.isEqual(rhs.h6)
            && lhs.bold.isEqual(rhs.bold)
            && lhs.italic.isEqual(rhs.italic)
            && lhs.boldItalic.isEqual(rhs.boldItalic)
            && lhs.link.isEqual(rhs.link)
            && lhs.inlineCode.isEqual(rhs.inlineCode)
            && lhs.fence.isEqual(rhs.fence)
            && lhs.list.isEqual(rhs.list)
            && lhs.foldMarker.isEqual(rhs.foldMarker)
            && lhs.table.isEqual(rhs.table)
            && lhs.strikethrough.isEqual(rhs.strikethrough)
            && lhs.footnote.isEqual(rhs.footnote)
            && lhs.callout.isEqual(rhs.callout)
    }
}

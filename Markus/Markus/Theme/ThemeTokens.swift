import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ThemeTokens: Equatable {
    var background: PlatformColorType
    var heading: PlatformColorType
    var body: PlatformColorType
    var link: PlatformColorType
    var inlineCode: PlatformColorType
    var fence: PlatformColorType
    var list: PlatformColorType
    var foldMarker: PlatformColorType
    var table: PlatformColorType
    var strikethrough: PlatformColorType
    var footnote: PlatformColorType

    static var `default`: ThemeTokens {
        NamedThemeCatalog.tokens(for: .daylight)
    }

    static func == (lhs: ThemeTokens, rhs: ThemeTokens) -> Bool {
        lhs.background.isEqual(rhs.background)
            && lhs.heading.isEqual(rhs.heading)
            && lhs.body.isEqual(rhs.body)
            && lhs.link.isEqual(rhs.link)
            && lhs.inlineCode.isEqual(rhs.inlineCode)
            && lhs.fence.isEqual(rhs.fence)
            && lhs.list.isEqual(rhs.list)
            && lhs.foldMarker.isEqual(rhs.foldMarker)
            && lhs.table.isEqual(rhs.table)
            && lhs.strikethrough.isEqual(rhs.strikethrough)
            && lhs.footnote.isEqual(rhs.footnote)
    }
}

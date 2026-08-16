import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ThemeTokens {
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
        ThemeTokens(
            background: color(red: 0.98, green: 0.98, blue: 0.96),
            heading: color(red: 0.12, green: 0.22, blue: 0.45),
            body: color(red: 0.15, green: 0.15, blue: 0.15),
            link: color(red: 0.10, green: 0.35, blue: 0.75),
            inlineCode: color(red: 0.55, green: 0.15, blue: 0.20),
            fence: color(red: 0.20, green: 0.35, blue: 0.25),
            list: color(red: 0.25, green: 0.25, blue: 0.30),
            foldMarker: color(red: 0.50, green: 0.50, blue: 0.55),
            table: color(red: 0.18, green: 0.28, blue: 0.38),
            strikethrough: color(red: 0.45, green: 0.45, blue: 0.45),
            footnote: color(red: 0.40, green: 0.32, blue: 0.18)
        )
    }

    private static func color(red: CGFloat, green: CGFloat, blue: CGFloat) -> PlatformColorType {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

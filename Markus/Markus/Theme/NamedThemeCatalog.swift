import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum NamedThemeID: String, CaseIterable, Equatable {
    case daylight
    case lampblack
    case fog
    case parchment
    case meadow
    case harbor

    var displayName: String {
        switch self {
        case .daylight: "Daylight"
        case .lampblack: "Lampblack"
        case .fog: "Fog"
        case .parchment: "Parchment"
        case .meadow: "Meadow"
        case .harbor: "Harbor"
        }
    }
}

enum NamedThemeCatalog {
    static func tokens(for id: NamedThemeID) -> ThemeTokens {
        switch id {
        case .daylight:
            ThemeTokens(
                background: color(0.98, 0.98, 0.96),
                heading: color(0.12, 0.22, 0.45),
                body: color(0.15, 0.15, 0.15),
                link: color(0.10, 0.35, 0.75),
                inlineCode: color(0.55, 0.15, 0.20),
                fence: color(0.20, 0.35, 0.25),
                list: color(0.25, 0.25, 0.30),
                foldMarker: color(0.50, 0.50, 0.55),
                table: color(0.18, 0.28, 0.38),
                strikethrough: color(0.45, 0.45, 0.45),
                footnote: color(0.40, 0.32, 0.18)
            )
        case .lampblack:
            ThemeTokens(
                background: color(0.08, 0.08, 0.09),
                heading: color(0.92, 0.82, 0.55),
                body: color(0.88, 0.86, 0.82),
                link: color(0.55, 0.75, 0.95),
                inlineCode: color(0.95, 0.55, 0.50),
                fence: color(0.55, 0.82, 0.62),
                list: color(0.75, 0.75, 0.78),
                foldMarker: color(0.50, 0.50, 0.55),
                table: color(0.70, 0.80, 0.88),
                strikethrough: color(0.55, 0.55, 0.55),
                footnote: color(0.78, 0.70, 0.50)
            )
        case .fog:
            ThemeTokens(
                background: color(0.90, 0.91, 0.93),
                heading: color(0.28, 0.32, 0.40),
                body: color(0.22, 0.24, 0.28),
                link: color(0.25, 0.40, 0.58),
                inlineCode: color(0.42, 0.22, 0.38),
                fence: color(0.28, 0.38, 0.36),
                list: color(0.32, 0.34, 0.40),
                foldMarker: color(0.48, 0.50, 0.54),
                table: color(0.30, 0.36, 0.44),
                strikethrough: color(0.50, 0.52, 0.55),
                footnote: color(0.40, 0.38, 0.32)
            )
        case .parchment:
            ThemeTokens(
                background: color(0.96, 0.92, 0.82),
                heading: color(0.42, 0.22, 0.10),
                body: color(0.22, 0.16, 0.10),
                link: color(0.38, 0.22, 0.48),
                inlineCode: color(0.58, 0.18, 0.12),
                fence: color(0.32, 0.28, 0.14),
                list: color(0.36, 0.26, 0.16),
                foldMarker: color(0.58, 0.50, 0.38),
                table: color(0.34, 0.24, 0.16),
                strikethrough: color(0.52, 0.46, 0.38),
                footnote: color(0.46, 0.34, 0.18)
            )
        case .meadow:
            ThemeTokens(
                background: color(0.94, 0.96, 0.90),
                heading: color(0.18, 0.38, 0.22),
                body: color(0.16, 0.22, 0.16),
                link: color(0.12, 0.42, 0.38),
                inlineCode: color(0.48, 0.22, 0.18),
                fence: color(0.22, 0.40, 0.28),
                list: color(0.28, 0.36, 0.24),
                foldMarker: color(0.48, 0.56, 0.46),
                table: color(0.22, 0.36, 0.30),
                strikethrough: color(0.46, 0.50, 0.44),
                footnote: color(0.36, 0.34, 0.18)
            )
        case .harbor:
            ThemeTokens(
                background: color(0.90, 0.94, 0.96),
                heading: color(0.10, 0.28, 0.42),
                body: color(0.12, 0.18, 0.28),
                link: color(0.08, 0.38, 0.62),
                inlineCode: color(0.50, 0.18, 0.28),
                fence: color(0.16, 0.36, 0.40),
                list: color(0.22, 0.28, 0.38),
                foldMarker: color(0.46, 0.54, 0.60),
                table: color(0.16, 0.32, 0.44),
                strikethrough: color(0.44, 0.50, 0.54),
                footnote: color(0.32, 0.30, 0.22)
            )
        }
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformColorType {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

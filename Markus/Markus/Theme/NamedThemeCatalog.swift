import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ThemeFamily: String, CaseIterable, Equatable, Hashable {
    case nord
    case monokai
    case solarized
    case github
    case catppuccin
    case gruvbox

    var displayName: String {
        switch self {
        case .nord: "Nord"
        case .monokai: "Monokai"
        case .solarized: "Solarized"
        case .github: "GitHub"
        case .catppuccin: "Catppuccin"
        case .gruvbox: "Gruvbox"
        }
    }
}

enum ThemeVariant: String, CaseIterable, Equatable, Hashable {
    case light
    case dark

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum NamedThemeCatalog {
    /// Placeholder recipes until ticket 04 ships twelve palettes.
    /// Light variants reuse v1.1 Daylight; dark variants reuse Lampblack.
    static func tokens(for family: ThemeFamily, variant: ThemeVariant) -> ThemeTokens {
        switch (family, variant) {
        case (_, .light):
            lightStandIn
        case (_, .dark):
            darkStandIn
        }
    }

    private static var lightStandIn: ThemeTokens {
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
    }

    private static var darkStandIn: ThemeTokens {
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
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformColorType {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

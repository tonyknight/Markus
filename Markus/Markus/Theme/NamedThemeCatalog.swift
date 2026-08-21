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
    /// Twelve original sRGB recipes inspired by the public look of each
    /// family. Values are hand-authored, not copied from a vendor file.
    static func tokens(for family: ThemeFamily, variant: ThemeVariant) -> ThemeTokens {
        switch (family, variant) {
        case (.nord, .light): nordLight
        case (.nord, .dark): nordDark
        case (.monokai, .light): monokaiLight
        case (.monokai, .dark): monokaiDark
        case (.solarized, .light): solarizedLight
        case (.solarized, .dark): solarizedDark
        case (.github, .light): githubLight
        case (.github, .dark): githubDark
        case (.catppuccin, .light): catppuccinLight
        case (.catppuccin, .dark): catppuccinDark
        case (.gruvbox, .light): gruvboxLight
        case (.gruvbox, .dark): gruvboxDark
        }
    }

    // MARK: - Nord (cool polar snow / polar night)

    private static var nordLight: ThemeTokens {
        recipe(
            background: (0.925, 0.933, 0.945),
            heading: (0.290, 0.455, 0.620),
            body: (0.180, 0.210, 0.265),
            link: (0.250, 0.430, 0.600),
            inlineCode: (0.620, 0.310, 0.355),
            fence: (0.280, 0.480, 0.450),
            list: (0.280, 0.325, 0.400),
            foldMarker: (0.380, 0.420, 0.480),
            table: (0.255, 0.375, 0.490),
            strikethrough: (0.480, 0.500, 0.530),
            footnote: (0.430, 0.385, 0.300)
        )
    }

    private static var nordDark: ThemeTokens {
        recipe(
            background: (0.175, 0.200, 0.245),
            heading: (0.530, 0.745, 0.805),
            body: (0.845, 0.870, 0.905),
            link: (0.560, 0.720, 0.860),
            inlineCode: (0.780, 0.600, 0.730),
            fence: (0.555, 0.735, 0.545),
            list: (0.750, 0.775, 0.820),
            foldMarker: (0.620, 0.660, 0.720),
            table: (0.530, 0.680, 0.790),
            strikethrough: (0.580, 0.600, 0.640),
            footnote: (0.860, 0.760, 0.540)
        )
    }

    // MARK: - Monokai (warm cream / charcoal, magenta + cyan)

    private static var monokaiLight: ThemeTokens {
        recipe(
            background: (0.980, 0.965, 0.925),
            heading: (0.620, 0.080, 0.280),
            body: (0.180, 0.175, 0.155),
            link: (0.050, 0.430, 0.500),
            inlineCode: (0.720, 0.360, 0.050),
            fence: (0.300, 0.500, 0.100),
            list: (0.280, 0.270, 0.250),
            foldMarker: (0.450, 0.430, 0.370),
            table: (0.380, 0.220, 0.560),
            strikethrough: (0.500, 0.480, 0.440),
            footnote: (0.520, 0.380, 0.120)
        )
    }

    private static var monokaiDark: ThemeTokens {
        recipe(
            background: (0.145, 0.148, 0.130),
            heading: (0.960, 0.280, 0.500),
            body: (0.960, 0.955, 0.930),
            link: (0.420, 0.840, 0.910),
            inlineCode: (0.980, 0.600, 0.200),
            fence: (0.660, 0.880, 0.280),
            list: (0.820, 0.810, 0.780),
            foldMarker: (0.580, 0.570, 0.500),
            table: (0.700, 0.560, 0.960),
            strikethrough: (0.560, 0.550, 0.500),
            footnote: (0.900, 0.850, 0.500)
        )
    }

    // MARK: - Solarized (cream paper / deep teal)

    private static var solarizedLight: ThemeTokens {
        recipe(
            background: (0.992, 0.965, 0.890),
            heading: (0.550, 0.400, 0.000),
            body: (0.220, 0.280, 0.300),
            link: (0.100, 0.400, 0.620),
            inlineCode: (0.720, 0.160, 0.140),
            fence: (0.100, 0.470, 0.440),
            list: (0.300, 0.350, 0.370),
            foldMarker: (0.450, 0.430, 0.350),
            table: (0.360, 0.370, 0.680),
            strikethrough: (0.500, 0.490, 0.430),
            footnote: (0.560, 0.340, 0.080)
        )
    }

    private static var solarizedDark: ThemeTokens {
        recipe(
            background: (0.000, 0.165, 0.210),
            heading: (0.850, 0.680, 0.150),
            body: (0.850, 0.880, 0.870),
            link: (0.480, 0.780, 0.920),
            inlineCode: (0.900, 0.500, 0.460),
            fence: (0.380, 0.800, 0.750),
            list: (0.740, 0.790, 0.790),
            foldMarker: (0.540, 0.640, 0.660),
            table: (0.680, 0.710, 0.940),
            strikethrough: (0.520, 0.580, 0.590),
            footnote: (0.900, 0.700, 0.350)
        )
    }

    // MARK: - GitHub (near-white / near-black, blue links)

    private static var githubLight: ThemeTokens {
        recipe(
            background: (0.988, 0.988, 0.990),
            heading: (0.090, 0.105, 0.130),
            body: (0.145, 0.160, 0.180),
            link: (0.035, 0.340, 0.700),
            inlineCode: (0.640, 0.090, 0.170),
            fence: (0.090, 0.350, 0.180),
            list: (0.220, 0.240, 0.260),
            foldMarker: (0.400, 0.425, 0.455),
            table: (0.118, 0.137, 0.157),
            strikethrough: (0.490, 0.510, 0.530),
            footnote: (0.380, 0.340, 0.250)
        )
    }

    private static var githubDark: ThemeTokens {
        recipe(
            background: (0.051, 0.067, 0.090),
            heading: (0.910, 0.925, 0.940),
            body: (0.900, 0.918, 0.937),
            link: (0.380, 0.650, 0.980),
            inlineCode: (0.960, 0.540, 0.590),
            fence: (0.520, 0.840, 0.610),
            list: (0.780, 0.800, 0.825),
            foldMarker: (0.540, 0.580, 0.640),
            table: (0.780, 0.820, 0.870),
            strikethrough: (0.520, 0.550, 0.590),
            footnote: (0.850, 0.770, 0.550)
        )
    }

    // MARK: - Catppuccin (latte pastel / mocha purple)

    private static var catppuccinLight: ThemeTokens {
        recipe(
            background: (0.937, 0.945, 0.960),
            heading: (0.300, 0.180, 0.680),
            body: (0.250, 0.260, 0.360),
            link: (0.080, 0.320, 0.820),
            inlineCode: (0.720, 0.040, 0.180),
            fence: (0.180, 0.500, 0.120),
            list: (0.320, 0.330, 0.420),
            foldMarker: (0.450, 0.455, 0.520),
            table: (0.720, 0.300, 0.020),
            strikethrough: (0.500, 0.505, 0.550),
            footnote: (0.700, 0.420, 0.050)
        )
    }

    private static var catppuccinDark: ThemeTokens {
        recipe(
            background: (0.118, 0.118, 0.180),
            heading: (0.796, 0.651, 0.969),
            body: (0.804, 0.839, 0.957),
            link: (0.580, 0.740, 0.990),
            inlineCode: (0.953, 0.545, 0.659),
            fence: (0.651, 0.890, 0.631),
            list: (0.730, 0.745, 0.860),
            foldMarker: (0.560, 0.570, 0.700),
            table: (0.980, 0.720, 0.560),
            strikethrough: (0.540, 0.550, 0.640),
            footnote: (0.980, 0.810, 0.590)
        )
    }

    // MARK: - Gruvbox (warm parchment / warm brown)

    private static var gruvboxLight: ThemeTokens {
        recipe(
            background: (0.984, 0.945, 0.780),
            heading: (0.520, 0.000, 0.020),
            body: (0.200, 0.185, 0.175),
            link: (0.020, 0.340, 0.400),
            inlineCode: (0.600, 0.180, 0.010),
            fence: (0.400, 0.380, 0.040),
            list: (0.280, 0.260, 0.230),
            foldMarker: (0.480, 0.420, 0.280),
            table: (0.480, 0.200, 0.380),
            strikethrough: (0.520, 0.480, 0.380),
            footnote: (0.600, 0.380, 0.050)
        )
    }

    private static var gruvboxDark: ThemeTokens {
        recipe(
            background: (0.157, 0.141, 0.133),
            heading: (0.984, 0.760, 0.220),
            body: (0.922, 0.859, 0.698),
            link: (0.560, 0.780, 0.720),
            inlineCode: (0.996, 0.560, 0.180),
            fence: (0.760, 0.770, 0.220),
            list: (0.830, 0.775, 0.650),
            foldMarker: (0.620, 0.570, 0.450),
            table: (0.850, 0.560, 0.640),
            strikethrough: (0.580, 0.540, 0.450),
            footnote: (0.980, 0.820, 0.420)
        )
    }

    private static func recipe(
        background: (CGFloat, CGFloat, CGFloat),
        heading: (CGFloat, CGFloat, CGFloat),
        body: (CGFloat, CGFloat, CGFloat),
        link: (CGFloat, CGFloat, CGFloat),
        inlineCode: (CGFloat, CGFloat, CGFloat),
        fence: (CGFloat, CGFloat, CGFloat),
        list: (CGFloat, CGFloat, CGFloat),
        foldMarker: (CGFloat, CGFloat, CGFloat),
        table: (CGFloat, CGFloat, CGFloat),
        strikethrough: (CGFloat, CGFloat, CGFloat),
        footnote: (CGFloat, CGFloat, CGFloat)
    ) -> ThemeTokens {
        ThemeTokens(
            background: color(background),
            heading: color(heading),
            body: color(body),
            link: color(link),
            inlineCode: color(inlineCode),
            fence: color(fence),
            list: color(list),
            foldMarker: color(foldMarker),
            table: color(table),
            strikethrough: color(strikethrough),
            footnote: color(footnote)
        )
    }

    private static func color(_ rgb: (CGFloat, CGFloat, CGFloat)) -> PlatformColorType {
        color(rgb.0, rgb.1, rgb.2)
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformColorType {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

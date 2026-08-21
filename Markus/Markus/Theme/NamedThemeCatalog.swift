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

    /// Picker-facing card title. v1.1 names (Daylight, Lampblack, Fog,
    /// Parchment, Meadow, Harbor) are not part of this API.
    func pickerTitle(variant: ThemeVariant) -> String {
        "\(displayName) \(variant.displayName)"
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
    /// Read-only at runtime: Use as Custom copies values into the custom
    /// store and never mutates these recipes (R7).
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
            h1: (0.200, 0.365, 0.530),
            h2: (0.250, 0.430, 0.580),
            h3: (0.310, 0.380, 0.560),
            h4: (0.200, 0.450, 0.440),
            h5: (0.360, 0.280, 0.460),
            h6: (0.300, 0.340, 0.400),
            body: (0.165, 0.195, 0.250),
            bold: (0.090, 0.110, 0.160),
            italic: (0.220, 0.280, 0.380),
            boldItalic: (0.120, 0.150, 0.230),
            link: (0.175, 0.355, 0.540),
            inlineCode: (0.620, 0.310, 0.355),
            fence: (0.280, 0.480, 0.450),
            list: (0.280, 0.325, 0.400),
            foldMarker: (0.330, 0.370, 0.430),
            table: (0.255, 0.375, 0.490),
            strikethrough: (0.480, 0.500, 0.530),
            footnote: (0.430, 0.385, 0.300),
            callout: (0.370, 0.510, 0.675)
        )
    }

    private static var nordDark: ThemeTokens {
        recipe(
            background: (0.175, 0.200, 0.245),
            h1: (0.530, 0.745, 0.805),
            h2: (0.533, 0.627, 0.757),
            h3: (0.706, 0.557, 0.678),
            h4: (0.639, 0.745, 0.549),
            h5: (0.816, 0.737, 0.545),
            h6: (0.650, 0.700, 0.780),
            body: (0.845, 0.870, 0.905),
            bold: (0.940, 0.950, 0.970),
            italic: (0.780, 0.800, 0.860),
            boldItalic: (0.880, 0.860, 0.920),
            link: (0.600, 0.760, 0.900),
            inlineCode: (0.780, 0.600, 0.730),
            fence: (0.555, 0.735, 0.545),
            list: (0.750, 0.775, 0.820),
            foldMarker: (0.660, 0.700, 0.760),
            table: (0.530, 0.680, 0.790),
            strikethrough: (0.580, 0.600, 0.640),
            footnote: (0.860, 0.760, 0.540),
            callout: (0.530, 0.745, 0.805)
        )
    }

    // MARK: - Monokai (warm cream / charcoal, magenta + cyan)

    private static var monokaiLight: ThemeTokens {
        recipe(
            background: (0.980, 0.965, 0.925),
            h1: (0.620, 0.080, 0.280),
            h2: (0.720, 0.360, 0.050),
            h3: (0.550, 0.420, 0.000),
            h4: (0.250, 0.450, 0.080),
            h5: (0.080, 0.420, 0.480),
            h6: (0.380, 0.220, 0.560),
            body: (0.160, 0.155, 0.135),
            bold: (0.080, 0.070, 0.050),
            italic: (0.280, 0.160, 0.220),
            boldItalic: (0.140, 0.080, 0.120),
            link: (0.030, 0.390, 0.460),
            inlineCode: (0.720, 0.360, 0.050),
            fence: (0.300, 0.500, 0.100),
            list: (0.280, 0.270, 0.250),
            foldMarker: (0.420, 0.400, 0.330),
            table: (0.380, 0.220, 0.560),
            strikethrough: (0.500, 0.480, 0.440),
            footnote: (0.520, 0.380, 0.120),
            callout: (0.030, 0.390, 0.460)
        )
    }

    private static var monokaiDark: ThemeTokens {
        recipe(
            background: (0.145, 0.148, 0.130),
            h1: (0.990, 0.450, 0.620),
            h2: (0.980, 0.600, 0.200),
            h3: (0.980, 0.900, 0.350),
            h4: (0.660, 0.880, 0.280),
            h5: (0.450, 0.860, 0.930),
            h6: (0.700, 0.560, 0.960),
            body: (0.960, 0.955, 0.930),
            bold: (1.000, 0.980, 0.950),
            italic: (0.900, 0.820, 0.880),
            boldItalic: (0.980, 0.880, 0.920),
            link: (0.450, 0.860, 0.930),
            inlineCode: (0.980, 0.600, 0.200),
            fence: (0.660, 0.880, 0.280),
            list: (0.820, 0.810, 0.780),
            foldMarker: (0.640, 0.630, 0.550),
            table: (0.700, 0.560, 0.960),
            strikethrough: (0.560, 0.550, 0.500),
            footnote: (0.900, 0.850, 0.500),
            callout: (0.450, 0.860, 0.930)
        )
    }

    // MARK: - Solarized (cream paper / deep teal)

    private static var solarizedLight: ThemeTokens {
        recipe(
            background: (0.992, 0.965, 0.890),
            h1: (0.500, 0.360, 0.000),
            h2: (0.720, 0.160, 0.140),
            h3: (0.800, 0.350, 0.050),
            h4: (0.360, 0.370, 0.680),
            h5: (0.150, 0.400, 0.520),
            h6: (0.100, 0.470, 0.440),
            body: (0.200, 0.255, 0.275),
            bold: (0.140, 0.180, 0.200),
            italic: (0.280, 0.240, 0.180),
            boldItalic: (0.180, 0.160, 0.140),
            link: (0.080, 0.360, 0.580),
            inlineCode: (0.720, 0.160, 0.140),
            fence: (0.100, 0.470, 0.440),
            list: (0.300, 0.350, 0.370),
            foldMarker: (0.410, 0.390, 0.300),
            table: (0.360, 0.370, 0.680),
            strikethrough: (0.500, 0.490, 0.430),
            footnote: (0.560, 0.340, 0.080),
            callout: (0.080, 0.360, 0.580)
        )
    }

    private static var solarizedDark: ThemeTokens {
        recipe(
            background: (0.000, 0.165, 0.210),
            h1: (0.850, 0.680, 0.150),
            h2: (0.900, 0.500, 0.460),
            h3: (0.900, 0.600, 0.200),
            h4: (0.680, 0.710, 0.940),
            h5: (0.500, 0.800, 0.940),
            h6: (0.380, 0.800, 0.750),
            body: (0.870, 0.900, 0.890),
            bold: (0.930, 0.940, 0.910),
            italic: (0.820, 0.850, 0.780),
            boldItalic: (0.900, 0.880, 0.800),
            link: (0.500, 0.800, 0.940),
            inlineCode: (0.900, 0.500, 0.460),
            fence: (0.380, 0.800, 0.750),
            list: (0.740, 0.790, 0.790),
            foldMarker: (0.580, 0.680, 0.700),
            table: (0.680, 0.710, 0.940),
            strikethrough: (0.520, 0.580, 0.590),
            footnote: (0.900, 0.700, 0.350),
            callout: (0.500, 0.800, 0.940)
        )
    }

    // MARK: - GitHub (near-white / near-black, blue links)

    private static var githubLight: ThemeTokens {
        recipe(
            background: (0.988, 0.988, 0.990),
            h1: (0.090, 0.105, 0.130),
            h2: (0.140, 0.160, 0.190),
            h3: (0.180, 0.140, 0.320),
            h4: (0.020, 0.280, 0.500),
            h5: (0.200, 0.280, 0.220),
            h6: (0.280, 0.300, 0.330),
            body: (0.130, 0.145, 0.165),
            bold: (0.050, 0.055, 0.070),
            italic: (0.180, 0.160, 0.200),
            boldItalic: (0.080, 0.070, 0.110),
            link: (0.020, 0.300, 0.640),
            inlineCode: (0.640, 0.090, 0.170),
            fence: (0.090, 0.350, 0.180),
            list: (0.220, 0.240, 0.260),
            foldMarker: (0.360, 0.385, 0.415),
            table: (0.118, 0.137, 0.157),
            strikethrough: (0.490, 0.510, 0.530),
            footnote: (0.380, 0.340, 0.250),
            callout: (0.020, 0.300, 0.640)
        )
    }

    private static var githubDark: ThemeTokens {
        recipe(
            background: (0.051, 0.067, 0.090),
            h1: (0.910, 0.925, 0.940),
            h2: (0.780, 0.840, 0.980),
            h3: (0.900, 0.780, 0.980),
            h4: (0.700, 0.900, 0.780),
            h5: (0.980, 0.860, 0.700),
            h6: (0.800, 0.820, 0.860),
            body: (0.900, 0.918, 0.937),
            bold: (1.000, 1.000, 1.000),
            italic: (0.850, 0.860, 0.920),
            boldItalic: (0.960, 0.940, 0.980),
            link: (0.420, 0.680, 0.990),
            inlineCode: (0.960, 0.540, 0.590),
            fence: (0.520, 0.840, 0.610),
            list: (0.780, 0.800, 0.825),
            foldMarker: (0.580, 0.620, 0.680),
            table: (0.780, 0.820, 0.870),
            strikethrough: (0.520, 0.550, 0.590),
            footnote: (0.850, 0.770, 0.550),
            callout: (0.420, 0.680, 0.990)
        )
    }

    // MARK: - Catppuccin (latte pastel / mocha purple)

    private static var catppuccinLight: ThemeTokens {
        recipe(
            background: (0.937, 0.945, 0.960),
            h1: (0.280, 0.150, 0.640),
            h2: (0.720, 0.040, 0.180),
            h3: (0.850, 0.280, 0.480),
            h4: (0.800, 0.450, 0.100),
            h5: (0.550, 0.420, 0.050),
            h6: (0.180, 0.400, 0.500),
            body: (0.230, 0.240, 0.340),
            bold: (0.160, 0.150, 0.260),
            italic: (0.320, 0.220, 0.400),
            boldItalic: (0.200, 0.140, 0.320),
            link: (0.060, 0.280, 0.760),
            inlineCode: (0.720, 0.040, 0.180),
            fence: (0.180, 0.500, 0.120),
            list: (0.320, 0.330, 0.420),
            foldMarker: (0.390, 0.395, 0.460),
            table: (0.720, 0.300, 0.020),
            strikethrough: (0.500, 0.505, 0.550),
            footnote: (0.700, 0.420, 0.050),
            callout: (0.060, 0.280, 0.760)
        )
    }

    private static var catppuccinDark: ThemeTokens {
        recipe(
            background: (0.118, 0.118, 0.180),
            h1: (0.796, 0.651, 0.969),
            h2: (0.953, 0.545, 0.659),
            h3: (0.953, 0.700, 0.800),
            h4: (0.980, 0.720, 0.560),
            h5: (0.980, 0.860, 0.550),
            h6: (0.580, 0.850, 0.820),
            body: (0.804, 0.839, 0.957),
            bold: (0.900, 0.910, 0.980),
            italic: (0.780, 0.720, 0.900),
            boldItalic: (0.880, 0.780, 0.960),
            link: (0.620, 0.770, 0.995),
            inlineCode: (0.953, 0.545, 0.659),
            fence: (0.651, 0.890, 0.631),
            list: (0.730, 0.745, 0.860),
            foldMarker: (0.620, 0.630, 0.760),
            table: (0.980, 0.720, 0.560),
            strikethrough: (0.540, 0.550, 0.640),
            footnote: (0.980, 0.810, 0.590),
            callout: (0.620, 0.770, 0.995)
        )
    }

    // MARK: - Gruvbox (warm paper / warm brown)

    private static var gruvboxLight: ThemeTokens {
        recipe(
            background: (0.984, 0.945, 0.780),
            h1: (0.520, 0.000, 0.020),
            h2: (0.600, 0.180, 0.010),
            h3: (0.550, 0.380, 0.000),
            h4: (0.400, 0.380, 0.040),
            h5: (0.080, 0.340, 0.300),
            h6: (0.480, 0.200, 0.380),
            body: (0.180, 0.165, 0.155),
            bold: (0.100, 0.080, 0.060),
            italic: (0.280, 0.180, 0.100),
            boldItalic: (0.160, 0.100, 0.070),
            link: (0.010, 0.300, 0.360),
            inlineCode: (0.600, 0.180, 0.010),
            fence: (0.400, 0.380, 0.040),
            list: (0.280, 0.260, 0.230),
            foldMarker: (0.440, 0.380, 0.230),
            table: (0.480, 0.200, 0.380),
            strikethrough: (0.520, 0.480, 0.380),
            footnote: (0.600, 0.380, 0.050),
            callout: (0.010, 0.300, 0.360)
        )
    }

    private static var gruvboxDark: ThemeTokens {
        recipe(
            background: (0.157, 0.141, 0.133),
            h1: (0.984, 0.760, 0.220),
            h2: (0.996, 0.560, 0.180),
            h3: (0.984, 0.480, 0.350),
            h4: (0.760, 0.770, 0.220),
            h5: (0.600, 0.820, 0.760),
            h6: (0.850, 0.560, 0.640),
            body: (0.935, 0.875, 0.720),
            bold: (0.980, 0.940, 0.800),
            italic: (0.900, 0.800, 0.620),
            boldItalic: (0.960, 0.860, 0.680),
            link: (0.600, 0.820, 0.760),
            inlineCode: (0.996, 0.560, 0.180),
            fence: (0.760, 0.770, 0.220),
            list: (0.830, 0.775, 0.650),
            foldMarker: (0.680, 0.620, 0.500),
            table: (0.850, 0.560, 0.640),
            strikethrough: (0.580, 0.540, 0.450),
            footnote: (0.980, 0.820, 0.420),
            callout: (0.600, 0.820, 0.760)
        )
    }

    private static func recipe(
        background: (CGFloat, CGFloat, CGFloat),
        h1: (CGFloat, CGFloat, CGFloat),
        h2: (CGFloat, CGFloat, CGFloat),
        h3: (CGFloat, CGFloat, CGFloat),
        h4: (CGFloat, CGFloat, CGFloat),
        h5: (CGFloat, CGFloat, CGFloat),
        h6: (CGFloat, CGFloat, CGFloat),
        body: (CGFloat, CGFloat, CGFloat),
        bold: (CGFloat, CGFloat, CGFloat),
        italic: (CGFloat, CGFloat, CGFloat),
        boldItalic: (CGFloat, CGFloat, CGFloat),
        link: (CGFloat, CGFloat, CGFloat),
        inlineCode: (CGFloat, CGFloat, CGFloat),
        fence: (CGFloat, CGFloat, CGFloat),
        list: (CGFloat, CGFloat, CGFloat),
        foldMarker: (CGFloat, CGFloat, CGFloat),
        table: (CGFloat, CGFloat, CGFloat),
        strikethrough: (CGFloat, CGFloat, CGFloat),
        footnote: (CGFloat, CGFloat, CGFloat),
        callout: (CGFloat, CGFloat, CGFloat)
    ) -> ThemeTokens {
        ThemeTokens(
            background: color(background),
            body: color(body),
            h1: color(h1),
            h2: color(h2),
            h3: color(h3),
            h4: color(h4),
            h5: color(h5),
            h6: color(h6),
            bold: color(bold),
            italic: color(italic),
            boldItalic: color(boldItalic),
            link: color(link),
            inlineCode: color(inlineCode),
            fence: color(fence),
            list: color(list),
            foldMarker: color(foldMarker),
            table: color(table),
            strikethrough: color(strikethrough),
            footnote: color(footnote),
            callout: color(callout)
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

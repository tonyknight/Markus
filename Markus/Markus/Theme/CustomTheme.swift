import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum CustomTextStyle: String, CaseIterable, Equatable, Hashable {
    case auto
    case light
    case dark
}

enum CustomTheme {
    static func tokens(background: PlatformColorType, textStyle: CustomTextStyle) -> ThemeTokens {
        let resolved = resolvedTextStyle(background: background, textStyle: textStyle)
        switch resolved {
        case .light:
            return ThemeTokens(
                background: background,
                body: color(0.16, 0.16, 0.16),
                h1: color(0.14, 0.20, 0.32),
                h2: color(0.16, 0.24, 0.40),
                h3: color(0.18, 0.28, 0.46),
                h4: color(0.22, 0.30, 0.42),
                h5: color(0.26, 0.30, 0.38),
                h6: color(0.28, 0.30, 0.34),
                bold: color(0.08, 0.08, 0.10),
                italic: color(0.22, 0.18, 0.28),
                boldItalic: color(0.12, 0.10, 0.20),
                link: color(0.12, 0.34, 0.62),
                inlineCode: color(0.52, 0.16, 0.20),
                fence: color(0.18, 0.34, 0.26),
                list: color(0.24, 0.26, 0.30),
                foldMarker: color(0.48, 0.48, 0.52),
                table: color(0.18, 0.26, 0.34),
                strikethrough: color(0.46, 0.46, 0.46),
                footnote: color(0.38, 0.32, 0.20),
                callout: color(0.20, 0.38, 0.58)
            )
        case .dark:
            return ThemeTokens(
                background: background,
                body: color(0.88, 0.88, 0.86),
                h1: color(0.90, 0.86, 0.72),
                h2: color(0.78, 0.84, 0.96),
                h3: color(0.92, 0.76, 0.88),
                h4: color(0.70, 0.88, 0.76),
                h5: color(0.96, 0.82, 0.62),
                h6: color(0.76, 0.78, 0.82),
                bold: color(0.96, 0.96, 0.94),
                italic: color(0.80, 0.82, 0.90),
                boldItalic: color(0.90, 0.86, 0.92),
                link: color(0.58, 0.78, 0.96),
                inlineCode: color(0.94, 0.62, 0.58),
                fence: color(0.58, 0.84, 0.68),
                list: color(0.76, 0.76, 0.80),
                foldMarker: color(0.54, 0.54, 0.58),
                table: color(0.72, 0.82, 0.88),
                strikethrough: color(0.58, 0.58, 0.58),
                footnote: color(0.80, 0.72, 0.54),
                callout: color(0.58, 0.78, 0.96)
            )
        case .auto:
            return tokens(background: background, textStyle: .light)
        }
    }

    static func resolvedTextStyle(background: PlatformColorType, textStyle: CustomTextStyle) -> CustomTextStyle {
        switch textStyle {
        case .light, .dark:
            return textStyle
        case .auto:
            return luminance(of: background) >= 0.5 ? .light : .dark
        }
    }

    private static func luminance(of color: PlatformColorType) -> CGFloat {
        #if os(macOS)
        let converted = color.usingColorSpace(.sRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let converted = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformColorType {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

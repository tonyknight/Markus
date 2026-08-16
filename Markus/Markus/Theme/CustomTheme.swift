import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum CustomTextStyle: String, CaseIterable, Equatable {
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
                heading: color(0.14, 0.20, 0.32),
                body: color(0.16, 0.16, 0.16),
                link: color(0.12, 0.34, 0.62),
                inlineCode: color(0.52, 0.16, 0.20),
                fence: color(0.18, 0.34, 0.26),
                list: color(0.24, 0.26, 0.30),
                foldMarker: color(0.48, 0.48, 0.52),
                table: color(0.18, 0.26, 0.34),
                strikethrough: color(0.46, 0.46, 0.46),
                footnote: color(0.38, 0.32, 0.20)
            )
        case .dark:
            return ThemeTokens(
                background: background,
                heading: color(0.90, 0.86, 0.72),
                body: color(0.88, 0.88, 0.86),
                link: color(0.58, 0.78, 0.96),
                inlineCode: color(0.94, 0.62, 0.58),
                fence: color(0.58, 0.84, 0.68),
                list: color(0.76, 0.76, 0.80),
                foldMarker: color(0.54, 0.54, 0.58),
                table: color(0.72, 0.82, 0.88),
                strikethrough: color(0.58, 0.58, 0.58),
                footnote: color(0.80, 0.72, 0.54)
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

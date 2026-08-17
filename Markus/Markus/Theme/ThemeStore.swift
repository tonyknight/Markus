import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ThemeSelection: Equatable, Hashable {
    case named(NamedThemeID)
    case custom

    var persistenceID: String {
        switch self {
        case .named(let id):
            return id.rawValue
        case .custom:
            return "custom"
        }
    }

    static func parse(_ raw: String?) -> ThemeSelection {
        guard let raw else { return .named(.daylight) }
        if raw == "custom" { return .custom }
        if let id = NamedThemeID(rawValue: raw) { return .named(id) }
        return .named(.daylight)
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let selectionKey = "markus.theme.selection"
    static let customBackgroundKey = "markus.theme.customBackground"
    static let customTextKey = "markus.theme.customText"

    /// The single app-scoped store. Every real document window/tab/scene
    /// is wired to this instance (`MarkdownDocument.init()` on macOS,
    /// `AppRootView` on iOS/iPadOS) so a theme change broadcasts to all of
    /// them (R9; J.27; Architecture component 6 "One app-scoped
    /// `ThemeStore`"). Deliberately not used as the default for
    /// `DocumentHost`'s other convenience initializers — those keep
    /// creating a fresh, isolated `ThemeStore()` so the many pre-existing
    /// tests that construct `DocumentHost` for unrelated concerns don't
    /// start sharing one global mutable store.
    static let shared = ThemeStore()

    let defaults: UserDefaults
    @Published private(set) var selection: ThemeSelection
    @Published private(set) var hoverSelection: ThemeSelection?
    @Published private(set) var customBackground: PlatformColorType
    @Published private(set) var customTextStyle: CustomTextStyle

    /// Fires after a *committed* theme change (selection or a custom-theme
    /// edit) — never for hover. `DocumentHost` subscribes to this to
    /// re-apply `committedTokens` to its real editor, which is what makes
    /// every open document repaint when *any* of them commits a theme
    /// change (R9). Kept separate from `objectWillChange` (which also
    /// fires on hover, for the proxy/chrome to redraw) so a hover in one
    /// window can never force every other open document to reparse —
    /// that would just relocate the "heavy and jarring" bug T02 removed,
    /// not fix it. Sent *after* the property write (unlike `@Published`,
    /// which publishes before the value is actually stored) so subscribers
    /// that read `committedTokens` synchronously always see the new value.
    let themeChanged = PassthroughSubject<Void, Never>()

    var persistedSelectionID: String? {
        defaults.string(forKey: Self.selectionKey)
    }

    var committedTokens: ThemeTokens {
        tokens(for: selection)
    }

    var displayedTokens: ThemeTokens {
        tokens(for: hoverSelection ?? selection)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selection = ThemeSelection.parse(defaults.string(forKey: Self.selectionKey))
        self.customBackground = Self.loadBackground(from: defaults) ?? NamedThemeCatalog.tokens(for: .daylight).background
        if let raw = defaults.string(forKey: Self.customTextKey), let style = CustomTextStyle(rawValue: raw) {
            self.customTextStyle = style
        } else {
            self.customTextStyle = .auto
        }
        if defaults.string(forKey: Self.selectionKey) == nil {
            defaults.set(ThemeSelection.named(.daylight).persistenceID, forKey: Self.selectionKey)
        }
    }

    func tokens(for selection: ThemeSelection) -> ThemeTokens {
        switch selection {
        case .named(let id):
            return NamedThemeCatalog.tokens(for: id)
        case .custom:
            return CustomTheme.tokens(background: customBackground, textStyle: customTextStyle)
        }
    }

    func select(_ selection: ThemeSelection) {
        self.selection = selection
        hoverSelection = nil
        defaults.set(selection.persistenceID, forKey: Self.selectionKey)
        objectWillChange.send()
        themeChanged.send(())
    }

    func beginHover(_ selection: ThemeSelection) {
        hoverSelection = selection
        objectWillChange.send()
    }

    func endHover() {
        hoverSelection = nil
        objectWillChange.send()
    }

    func setCustomBackground(_ color: PlatformColorType) {
        customBackground = color
        defaults.set(Self.encodeColor(color), forKey: Self.customBackgroundKey)
        objectWillChange.send()
        themeChanged.send(())
    }

    func setCustomTextStyle(_ style: CustomTextStyle) {
        customTextStyle = style
        defaults.set(style.rawValue, forKey: Self.customTextKey)
        objectWillChange.send()
        themeChanged.send(())
    }

    private static func encodeColor(_ color: PlatformColorType) -> [Double] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if os(macOS)
        let converted = color.usingColorSpace(.sRGB) ?? color
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return [Double(red), Double(green), Double(blue), Double(alpha)]
    }

    private static func loadBackground(from defaults: UserDefaults) -> PlatformColorType? {
        guard let values = defaults.array(forKey: customBackgroundKey) as? [Double], values.count == 4 else {
            return nil
        }
        let red = CGFloat(values[0])
        let green = CGFloat(values[1])
        let blue = CGFloat(values[2])
        let alpha = CGFloat(values[3])
        #if os(macOS)
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }
}

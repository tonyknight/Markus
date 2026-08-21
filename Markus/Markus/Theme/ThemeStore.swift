import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ThemeSelection: Equatable, Hashable {
    case named(ThemeFamily)
    case custom

    var persistenceID: String {
        switch self {
        case .named(let family):
            return family.rawValue
        case .custom:
            return "custom"
        }
    }

    static func parse(_ raw: String?) -> ThemeSelection {
        guard let raw else { return .named(.nord) }
        if raw == "custom" { return .custom }
        if let family = ThemeFamily(rawValue: raw) { return .named(family) }
        switch raw {
        case "daylight", "fog", "parchment", "meadow", "harbor", "lampblack":
            return .named(.nord)
        default:
            return .named(.nord)
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let selectionKey = "markus.theme.selection"
    static let followSystemKey = "markus.theme.followSystem"
    static let pinnedVariantKey = "markus.theme.pinnedVariant"
    static let customBackgroundKey = "markus.theme.customBackground"
    static let customTextKey = "markus.theme.customText"
    static let customHeadingKey = "markus.theme.customHeading"
    static let customBodyKey = "markus.theme.customBody"
    static let customLinkKey = "markus.theme.customLink"
    static let customFenceKey = "markus.theme.customFence"

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
    @Published private(set) var followSystem: Bool
    @Published private(set) var pinnedVariant: ThemeVariant
    @Published private(set) var customBackground: PlatformColorType
    @Published private(set) var customTextStyle: CustomTextStyle
    // `nil` means "not yet individually customized" — the custom theme
    // falls back to `CustomTheme.tokens`'s auto-derived value for that
    // element (kept coherent with `customBackground`/`customTextStyle`)
    // until the user explicitly picks a color for it.
    @Published private(set) var customHeading: PlatformColorType?
    @Published private(set) var customBody: PlatformColorType?
    @Published private(set) var customLink: PlatformColorType?
    @Published private(set) var customFence: PlatformColorType?

    /// Leftover for the iOS `ThemePickerView` proxy (`displayedTokens`).
    /// The macOS Appearance page does not read or write this — its hover
    /// is `@State` on `AppearanceSettingsView`, so it cannot stick after
    /// close or into a second Settings window (R12, N2). Never persisted.
    private(set) var hoverTokens: ThemeTokens?

    /// Fires after a *committed* theme change (selection, follow toggle,
    /// custom-theme edit, or a Follow-on system appearance remap) — never
    /// for hover (N2). The only sender is `broadcastCommit`. `DocumentHost`
    /// subscribes to re-apply `committedTokens` to its real editor.
    /// Kept separate from `objectWillChange` (which also fires on hover,
    /// for the proxy/chrome to redraw) so a hover in one window can never
    /// force every other open document to reparse. Sent *after* the
    /// property write (unlike `@Published`, which publishes before the
    /// value is actually stored) so subscribers that read
    /// `committedTokens` synchronously always see the new value.
    let themeChanged = PassthroughSubject<Void, Never>()

    private var appearanceObservation: NSKeyValueObservation?
    private var appearanceObserver: NSObjectProtocol?
    private var lastFollowedSystemIsDark: Bool?

    var persistedSelectionID: String? {
        defaults.string(forKey: Self.selectionKey)
    }

    var systemIsDark: Bool {
        #if os(macOS)
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
        UITraitCollection.current.userInterfaceStyle == .dark
        #endif
    }

    var appliedVariant: ThemeVariant {
        if followSystem {
            return systemIsDark ? .dark : .light
        }
        return pinnedVariant
    }

    var committedTokens: ThemeTokens {
        tokens(for: selection)
    }

    var displayedTokens: ThemeTokens {
        hoverTokens ?? committedTokens
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawSelection = defaults.string(forKey: Self.selectionKey)
        self.selection = ThemeSelection.parse(rawSelection)
        self.pinnedVariant = Self.loadPinnedVariant(from: defaults, rawSelection: rawSelection)
        self.followSystem = Self.loadFollowSystem(from: defaults, rawSelection: rawSelection)
        self.customBackground = Self.loadBackground(from: defaults)
            ?? NamedThemeCatalog.tokens(for: .nord, variant: .light).background
        if let raw = defaults.string(forKey: Self.customTextKey), let style = CustomTextStyle(rawValue: raw) {
            self.customTextStyle = style
        } else {
            self.customTextStyle = .auto
        }
        self.hoverTokens = nil
        self.customHeading = Self.loadColor(from: defaults, key: Self.customHeadingKey)
        self.customBody = Self.loadColor(from: defaults, key: Self.customBodyKey)
        self.customLink = Self.loadColor(from: defaults, key: Self.customLinkKey)
        self.customFence = Self.loadColor(from: defaults, key: Self.customFenceKey)
        Self.persistMigratedStateIfNeeded(
            defaults: defaults,
            rawSelection: rawSelection,
            selection: selection,
            followSystem: followSystem,
            pinnedVariant: pinnedVariant
        )
        startObservingSystemAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    func tokens(for selection: ThemeSelection) -> ThemeTokens {
        switch selection {
        case .named(let family):
            let variant: ThemeVariant
            if followSystem {
                variant = systemIsDark ? .dark : .light
            } else {
                variant = pinnedVariant
            }
            return NamedThemeCatalog.tokens(for: family, variant: variant)
        case .custom:
            var tokens = CustomTheme.tokens(background: customBackground, textStyle: customTextStyle)
            if let customHeading {
                tokens.h1 = customHeading
                tokens.h2 = customHeading
                tokens.h3 = customHeading
                tokens.h4 = customHeading
                tokens.h5 = customHeading
                tokens.h6 = customHeading
            }
            if let customBody { tokens.body = customBody }
            if let customLink { tokens.link = customLink }
            if let customFence { tokens.fence = customFence }
            return tokens
        }
    }

    func isShowing(family: ThemeFamily, variant: ThemeVariant) -> Bool {
        guard case .named(let selected) = selection, selected == family else { return false }
        return appliedVariant == variant
    }

    func select(_ selection: ThemeSelection) {
        self.selection = selection
        defaults.set(selection.persistenceID, forKey: Self.selectionKey)
        broadcastCommit()
    }

    func selectNamed(_ family: ThemeFamily, variant: ThemeVariant) {
        selection = .named(family)
        if !followSystem {
            pinnedVariant = variant
            defaults.set(variant.rawValue, forKey: Self.pinnedVariantKey)
        }
        defaults.set(selection.persistenceID, forKey: Self.selectionKey)
        broadcastCommit()
    }

    func setFollowSystem(_ enabled: Bool) {
        if followSystem && !enabled {
            pinnedVariant = systemIsDark ? .dark : .light
            defaults.set(pinnedVariant.rawValue, forKey: Self.pinnedVariantKey)
        }
        followSystem = enabled
        defaults.set(enabled, forKey: Self.followSystemKey)
        lastFollowedSystemIsDark = enabled ? systemIsDark : nil
        broadcastCommit()
    }

    /// SwiftUI `colorScheme` / iOS trait changes call this so Follow can
    /// remap named families without a sticky hover (R5). No-op for Custom.
    func noteSystemAppearance() {
        handleSystemAppearanceChange()
    }

    /// iOS `ThemePickerView` proxy only. Must never call `broadcastCommit`
    /// / `themeChanged` (N2). macOS Appearance hover is view-local and
    /// must not call this.
    func beginHover(_ tokens: ThemeTokens) {
        hoverTokens = tokens
        objectWillChange.send()
    }

    /// iOS `ThemePickerView` proxy only. Must never call `broadcastCommit`
    /// / `themeChanged` (N2). macOS Appearance hover is view-local and
    /// must not call this.
    func endHover() {
        hoverTokens = nil
        objectWillChange.send()
    }

    func setCustomBackground(_ color: PlatformColorType) {
        customBackground = color
        defaults.set(Self.encodeColor(color), forKey: Self.customBackgroundKey)
        broadcastCommit()
    }

    func setCustomTextStyle(_ style: CustomTextStyle) {
        customTextStyle = style
        defaults.set(style.rawValue, forKey: Self.customTextKey)
        broadcastCommit()
    }

    func setCustomHeading(_ color: PlatformColorType) {
        customHeading = color
        defaults.set(Self.encodeColor(color), forKey: Self.customHeadingKey)
        broadcastCommit()
    }

    func setCustomBody(_ color: PlatformColorType) {
        customBody = color
        defaults.set(Self.encodeColor(color), forKey: Self.customBodyKey)
        broadcastCommit()
    }

    func setCustomLink(_ color: PlatformColorType) {
        customLink = color
        defaults.set(Self.encodeColor(color), forKey: Self.customLinkKey)
        broadcastCommit()
    }

    func setCustomFence(_ color: PlatformColorType) {
        customFence = color
        defaults.set(Self.encodeColor(color), forKey: Self.customFenceKey)
        broadcastCommit()
    }

    private func startObservingSystemAppearance() {
        lastFollowedSystemIsDark = systemIsDark
        #if os(macOS)
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.handleSystemAppearanceChange()
            }
        }
        #else
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemAppearanceChange()
            }
        }
        #endif
    }

    /// Remap named+follow tokens from the current system appearance and
    /// broadcast so every open document repaints. Custom is unchanged.
    /// Appearance flips are applies, not hover, so they use `themeChanged`.
    private func handleSystemAppearanceChange() {
        guard followSystem, case .named = selection else { return }
        let isDark = systemIsDark
        if lastFollowedSystemIsDark == isDark { return }
        lastFollowedSystemIsDark = isDark
        broadcastCommit(clearHover: false)
    }

    /// The only path that sends `themeChanged`. Hover must not call this (N2).
    private func broadcastCommit(clearHover: Bool = true) {
        if clearHover {
            hoverTokens = nil
        }
        objectWillChange.send()
        themeChanged.send(())
    }

    private static func loadFollowSystem(from defaults: UserDefaults, rawSelection: String?) -> Bool {
        if defaults.object(forKey: followSystemKey) != nil {
            return defaults.bool(forKey: followSystemKey)
        }
        // New install: Follow on. v1.1 relaunch (selection already stored): pin the old choice.
        return rawSelection == nil
    }

    private static func loadPinnedVariant(from defaults: UserDefaults, rawSelection: String?) -> ThemeVariant {
        if let raw = defaults.string(forKey: pinnedVariantKey), let variant = ThemeVariant(rawValue: raw) {
            return variant
        }
        if rawSelection == "lampblack" {
            return .dark
        }
        return .light
    }

    private static func persistMigratedStateIfNeeded(
        defaults: UserDefaults,
        rawSelection: String?,
        selection: ThemeSelection,
        followSystem: Bool,
        pinnedVariant: ThemeVariant
    ) {
        if rawSelection == nil {
            defaults.set(selection.persistenceID, forKey: selectionKey)
            defaults.set(followSystem, forKey: followSystemKey)
            defaults.set(pinnedVariant.rawValue, forKey: pinnedVariantKey)
            return
        }
        if ThemeFamily(rawValue: rawSelection ?? "") == nil, rawSelection != "custom" {
            defaults.set(selection.persistenceID, forKey: selectionKey)
        }
        if defaults.object(forKey: followSystemKey) == nil {
            defaults.set(followSystem, forKey: followSystemKey)
        }
        if defaults.object(forKey: pinnedVariantKey) == nil {
            defaults.set(pinnedVariant.rawValue, forKey: pinnedVariantKey)
        }
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
        loadColor(from: defaults, key: customBackgroundKey)
    }

    private static func loadColor(from defaults: UserDefaults, key: String) -> PlatformColorType? {
        guard let values = defaults.array(forKey: key) as? [Double], values.count == 4 else {
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

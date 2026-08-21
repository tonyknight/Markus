import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ThemeChrome {
    static let hostsPickerInSettings = true

    static var showsHoverPreview: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static let sampleMarkdown = """
    # Heading
    Body with a [link](https://example.com) and `code`.
    """

    @MainActor
    static func select(_ selection: ThemeSelection, on host: DocumentHost) {
        host.applyTheme(selection)
    }

    @MainActor
    static func selectNamed(_ family: ThemeFamily, variant: ThemeVariant, on host: DocumentHost) {
        host.applyNamedTheme(family, variant: variant)
    }

    @MainActor
    static func preview(_ tokens: ThemeTokens?, on host: DocumentHost) {
        host.previewTheme(tokens)
    }

    /// Builds the single shared proxy document shown below the preset and
    /// custom cards. Hovering a card previews that card's theme in this
    /// proxy only; the real open document is never touched by hover (R8;
    /// C.9).
    @MainActor
    static func makeProxyView(tokens: ThemeTokens) -> FoldingTextView {
        let view = FoldingTextView()
        view.loadMarkdown(sampleMarkdown)
        view.setMode(.preview)
        view.setTheme(tokens)
        view.configureAsThemeProxy()
        return view
    }
}

struct ThemePickerView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Themes")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(ThemeFamily.allCases, id: \.self) { family in
                        ForEach(ThemeVariant.allCases, id: \.self) { variant in
                            ThemeCard(
                                title: family.pickerTitle(variant: variant),
                                tokens: NamedThemeCatalog.tokens(for: family, variant: variant),
                                isSelected: host.themeStore.isShowing(family: family, variant: variant)
                            ) {
                                ThemeChrome.selectNamed(family, variant: variant, on: host)
                            } onHover: { hovering in
                                guard ThemeChrome.showsHoverPreview else { return }
                                ThemeChrome.preview(
                                    hovering ? NamedThemeCatalog.tokens(for: family, variant: variant) : nil,
                                    on: host
                                )
                            }
                        }
                    }
                    ThemeCard(
                        title: "Custom",
                        tokens: host.themeStore.tokens(for: .custom),
                        isSelected: host.themeStore.selection == .custom
                    ) {
                        ThemeChrome.select(.custom, on: host)
                    } onHover: { hovering in
                        guard ThemeChrome.showsHoverPreview else { return }
                        ThemeChrome.preview(hovering ? host.themeStore.tokens(for: .custom) : nil, on: host)
                    }
                }
                if host.themeStore.selection == .custom {
                    customControls
                }
                ThemeProxyRepresentable(tokens: host.themeStore.displayedTokens)
                    .frame(minHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Every `set` below defers to the next run-loop turn:
            // SwiftUI invokes these synchronously as part of its own
            // view-update transaction for the picker, and mutating the
            // published `ThemeStore` state synchronously from inside a
            // Binding.set triggers "Publishing changes from within view
            // updates is not allowed" — the same bug confirmed and fixed
            // for the Source/Preview mode picker (`ModeChrome.swift`).
            ColorPicker(
                "Background",
                selection: Binding(
                    get: { colorFromPlatform(host.themeStore.customBackground) },
                    set: { newValue in
                        let color = platformColor(from: newValue)
                        DispatchQueue.main.async { host.setCustomBackground(color) }
                    }
                )
            )
            Picker("Text style", selection: Binding(
                get: { host.themeStore.customTextStyle },
                set: { newValue in
                    DispatchQueue.main.async { host.setCustomTextStyle(newValue) }
                }
            )) {
                Text("Auto").tag(CustomTextStyle.auto)
                Text("Light").tag(CustomTextStyle.light)
                Text("Dark").tag(CustomTextStyle.dark)
            }
            .pickerStyle(.segmented)

            // Text style above only governs the elements not listed here
            // (inline code, lists, fold markers, tables, strikethrough,
            // footnotes) — these four are independently overridable and,
            // once picked, no longer move when Text style changes.
            ColorPicker(
                "Headings (# ##)",
                selection: Binding(
                    get: { colorFromPlatform(host.themeStore.tokens(for: .custom).h1) },
                    set: { newValue in
                        let color = platformColor(from: newValue)
                        DispatchQueue.main.async { host.setCustomHeading(color) }
                    }
                )
            )
            ColorPicker(
                "Normal text",
                selection: Binding(
                    get: { colorFromPlatform(host.themeStore.tokens(for: .custom).body) },
                    set: { newValue in
                        let color = platformColor(from: newValue)
                        DispatchQueue.main.async { host.setCustomBody(color) }
                    }
                )
            )
            ColorPicker(
                "Links",
                selection: Binding(
                    get: { colorFromPlatform(host.themeStore.tokens(for: .custom).link) },
                    set: { newValue in
                        let color = platformColor(from: newValue)
                        DispatchQueue.main.async { host.setCustomLink(color) }
                    }
                )
            )
            ColorPicker(
                "Code blocks",
                selection: Binding(
                    get: { colorFromPlatform(host.themeStore.tokens(for: .custom).fence) },
                    set: { newValue in
                        let color = platformColor(from: newValue)
                        DispatchQueue.main.async { host.setCustomFence(color) }
                    }
                )
            )
        }
    }

    private func colorFromPlatform(_ color: PlatformColorType) -> Color {
        #if os(macOS)
        Color(nsColor: color)
        #else
        Color(uiColor: color)
        #endif
    }

    private func platformColor(from color: Color) -> PlatformColorType {
        #if os(macOS)
        NSColor(color)
        #else
        UIColor(color)
        #endif
    }
}

struct ThemeCard: View {
    let title: String
    let tokens: ThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ThemeSwatch(tokens: tokens)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            onHover(hovering)
        }
        #endif
    }
}

/// A card's miniature theme preview, drawn entirely in SwiftUI (no
/// embedded `NSViewRepresentable`/`UIViewRepresentable`). Cards used to
/// embed a real `FoldingTextView` here (`ThemeProxyRepresentable`, now
/// used only by the single proxy document below the grid) — that embed
/// was the actual cause of the "cards cannot be selected" bug: a click landing
/// over the embedded view's region never reached the card's `Button`,
/// even though the embedded view's own `hitTest` already returned `nil`.
/// A plain SwiftUI view can't intercept AppKit/UIKit hit-testing that
/// way, so this swatch dissolves the bug by construction. The fill is
/// deliberately never `.clear` — a fully transparent region was
/// separately observed to fail hit-testing too in the same real-event
/// test harness, unrelated to the embedded-view bug.
private struct ThemeSwatch: View {
    let tokens: ThemeTokens

    var body: some View {
        ZStack(alignment: .topLeading) {
            colorFromPlatform(tokens.background)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorFromPlatform(tokens.h1))
                    .frame(width: 64, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorFromPlatform(tokens.body))
                    .frame(width: 96, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorFromPlatform(tokens.body))
                    .frame(width: 72, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorFromPlatform(tokens.link))
                    .frame(width: 44, height: 5)
            }
            .padding(10)
        }
    }

    private func colorFromPlatform(_ color: PlatformColorType) -> Color {
        #if os(macOS)
        Color(nsColor: color)
        #else
        Color(uiColor: color)
        #endif
    }
}

/// The single shared proxy document below the cards. Read-only (not the
/// real open document) — hover repaints only this view via
/// `updateNSView`/`updateUIView`, never `DocumentHost.session.editor`.
#if os(macOS)
private struct ThemeProxyRepresentable: NSViewRepresentable {
    var tokens: ThemeTokens

    func makeNSView(context: Context) -> FoldingTextView {
        ThemeChrome.makeProxyView(tokens: tokens)
    }

    func updateNSView(_ nsView: FoldingTextView, context: Context) {
        nsView.setTheme(tokens)
        nsView.ensureLayout()
    }
}
#else
private struct ThemeProxyRepresentable: UIViewRepresentable {
    var tokens: ThemeTokens

    func makeUIView(context: Context) -> FoldingTextView {
        ThemeChrome.makeProxyView(tokens: tokens)
    }

    func updateUIView(_ uiView: FoldingTextView, context: Context) {
        uiView.setTheme(tokens)
        uiView.ensureLayout()
    }
}
#endif

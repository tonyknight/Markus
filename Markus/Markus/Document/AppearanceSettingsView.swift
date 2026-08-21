#if os(macOS)
import AppKit
import SwiftUI

/// Appearance page inside the Settings window: Follow System, variant
/// cards plus Custom, and a real Preview proxy. Hover is `@State` on this
/// view — not `ThemeStore.hoverTokens` — so a second Settings window
/// cannot inherit it, and close/apply clears it (R3, R12, N2).
struct AppearanceSettingsView: View {
    @ObservedObject private var store = ThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var hoveredTokens: ThemeTokens?

    private var proxyTokens: ThemeTokens {
        hoveredTokens ?? store.committedTokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            followSystemControl
            GeometryReader { geo in
                let stackVertically = geo.size.width < 540
                if stackVertically {
                    VStack(alignment: .leading, spacing: 16) {
                        ScrollView {
                            cardGrid
                        }
                        proxyColumn
                            .frame(minHeight: 240)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView {
                            cardGrid
                        }
                        proxyColumn
                            .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { hoveredTokens = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                hoveredTokens = nil
            }
        }
        .accessibilityIdentifier("settings.appearance.view")
    }

    private var followSystemControl: some View {
        Toggle(
            "Follow System Appearance",
            isOn: Binding(
                get: { store.followSystem },
                set: { newValue in
                    hoveredTokens = nil
                    DispatchQueue.main.async {
                        store.setFollowSystem(newValue)
                    }
                }
            )
        )
        .toggleStyle(.checkbox)
        .disabled(store.selection == .custom)
        .help(
            store.selection == .custom
                ? "Follow System applies to named families only."
                : "Use the selected family’s Light or Dark variant from macOS appearance."
        )
        .accessibilityIdentifier("settings.appearance.followSystem")
    }

    private var cardGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: 12)],
            spacing: 12
        ) {
            ForEach(ThemeFamily.allCases, id: \.self) { family in
                ForEach(ThemeVariant.allCases, id: \.self) { variant in
                    let tokens = NamedThemeCatalog.tokens(for: family, variant: variant)
                    AppearanceThemeCard(
                        title: family.pickerTitle(variant: variant),
                        tokens: tokens,
                        isSelected: store.isShowing(family: family, variant: variant),
                        onSelect: {
                            commitNamed(family, variant: variant)
                        },
                        onHover: { hovering in
                            hoveredTokens = hovering ? tokens : nil
                        }
                    )
                    .accessibilityIdentifier(
                        "settings.appearance.card.\(family.rawValue).\(variant.rawValue)"
                    )
                }
            }
            AppearanceThemeCard(
                title: "Custom",
                tokens: store.tokens(for: .custom),
                isSelected: store.selection == .custom,
                onSelect: {
                    commitCustom()
                },
                onHover: { hovering in
                    hoveredTokens = hovering ? store.tokens(for: .custom) : nil
                }
            )
            .accessibilityIdentifier("settings.appearance.card.custom")
        }
    }

    private var proxyColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AppearanceThemeProxy(tokens: proxyTokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
        .accessibilityIdentifier("settings.appearance.proxy")
    }

    /// Commits through `ThemeStore.shared` so `themeChanged` repaints every
    /// open document. Clears local hover so apply does not leave a preview
    /// overlay (R3, N2).
    private func commitNamed(_ family: ThemeFamily, variant: ThemeVariant) {
        hoveredTokens = nil
        store.selectNamed(family, variant: variant)
    }

    private func commitCustom() {
        hoveredTokens = nil
        store.select(.custom)
    }
}

/// Card chrome for the Appearance grid. Snippet and chips are SwiftUI
/// only — an embedded `FoldingTextView` would swallow clicks.
private struct AppearanceThemeCard: View {
    let title: String
    let tokens: ThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                snippet
                    .frame(height: 72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                chipStrip
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Selected")
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
    }

    private var snippet: some View {
        ZStack(alignment: .topLeading) {
            colorFromPlatform(tokens.background)
            VStack(alignment: .leading, spacing: 4) {
                Text("# Title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colorFromPlatform(tokens.h1))
                Text("Body with a link")
                    .font(.system(size: 9))
                    .foregroundStyle(colorFromPlatform(tokens.body))
                Text("example.com")
                    .font(.system(size: 9))
                    .foregroundStyle(colorFromPlatform(tokens.link))
            }
            .padding(8)
        }
    }

    private var chipStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(chipColors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    /// Current token fields only — ticket 06 owns H1–H6 / emphasis / callout.
    private var chipColors: [Color] {
        [
            tokens.h1,
            tokens.body,
            tokens.link,
            tokens.inlineCode,
            tokens.fence,
            tokens.list,
        ].map(colorFromPlatform)
    }

    private func colorFromPlatform(_ color: PlatformColorType) -> Color {
        Color(nsColor: color)
    }
}

/// Real Markus Preview of `ThemeChrome.sampleMarkdown`. Theme updates
/// paint this view only; the open document stays on committed tokens.
private struct AppearanceThemeProxy: NSViewRepresentable {
    var tokens: ThemeTokens

    func makeNSView(context: Context) -> FoldingTextView {
        ThemeChrome.makeProxyView(tokens: tokens)
    }

    func updateNSView(_ nsView: FoldingTextView, context: Context) {
        nsView.setTheme(tokens)
        nsView.ensureLayout()
    }
}
#endif

#if os(macOS)
import AppKit
import SwiftUI

/// Appearance page inside the Settings window: Follow System plus a
/// wrapping grid of one card per catalog variant and Custom. Click
/// commits on `ThemeStore.shared` so every open document updates.
/// Hover and the GFM proxy column land in ticket 05 T02.
struct AppearanceSettingsView: View {
    @ObservedObject private var store = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            followSystemControl
            ScrollView {
                cardGrid
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("settings.appearance.view")
    }

    private var followSystemControl: some View {
        Toggle(
            "Follow System Appearance",
            isOn: Binding(
                get: { store.followSystem },
                set: { newValue in
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
                    AppearanceThemeCard(
                        title: family.pickerTitle(variant: variant),
                        tokens: NamedThemeCatalog.tokens(for: family, variant: variant),
                        isSelected: store.isShowing(family: family, variant: variant)
                    ) {
                        store.selectNamed(family, variant: variant)
                    }
                    .accessibilityIdentifier(
                        "settings.appearance.card.\(family.rawValue).\(variant.rawValue)"
                    )
                }
            }
            AppearanceThemeCard(
                title: "Custom",
                tokens: store.tokens(for: .custom),
                isSelected: store.selection == .custom
            ) {
                store.select(.custom)
            }
            .accessibilityIdentifier("settings.appearance.card.custom")
        }
    }
}

/// Card chrome for the Appearance grid. Snippet and chips are SwiftUI
/// only — an embedded `FoldingTextView` would swallow clicks.
private struct AppearanceThemeCard: View {
    let title: String
    let tokens: ThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void

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
    }

    private var snippet: some View {
        ZStack(alignment: .topLeading) {
            colorFromPlatform(tokens.background)
            VStack(alignment: .leading, spacing: 4) {
                Text("# Title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colorFromPlatform(tokens.heading))
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
            tokens.heading,
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
#endif

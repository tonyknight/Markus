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
    @State private var variantFilter: ThemeVariant = .light
    @State private var cloneFamily: ThemeFamily?
    @State private var cloneVariant: ThemeVariant?
    @State private var confirmReplaceCustom = false
    @State private var headingsExpanded = true
    @State private var emphasisExpanded = false
    @State private var blocksExpanded = false
    @State private var otherExpanded = false

    private var proxyTokens: ThemeTokens {
        hoveredTokens ?? store.committedTokens
    }

    private var cloneSourceTokens: ThemeTokens? {
        guard let cloneFamily, let cloneVariant else { return nil }
        return NamedThemeCatalog.tokens(for: cloneFamily, variant: cloneVariant)
    }

    private var cloneSourceTitle: String? {
        guard let cloneFamily, let cloneVariant else { return nil }
        return cloneFamily.pickerTitle(variant: cloneVariant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            appearanceHeader
            GeometryReader { geo in
                let stackVertically = geo.size.width < 540
                if stackVertically {
                    VStack(alignment: .leading, spacing: 16) {
                        catalogScroll
                        proxyColumn
                            .frame(minHeight: 240)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        catalogScroll
                        proxyColumn
                            .frame(minWidth: 260)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            variantFilter = store.appliedVariant
            seedCloneSourceIfNeeded()
        }
        .onDisappear { hoveredTokens = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                hoveredTokens = nil
            }
        }
        .alert("Replace Custom Theme?", isPresented: $confirmReplaceCustom) {
            Button("Replace", role: .destructive) {
                applyClone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Custom already has colors that differ from \(cloneSourceTitle ?? "this theme"). Replacing them cannot be undone."
            )
        }
        .accessibilityIdentifier("settings.appearance.view")
    }

    private var appearanceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            followSystemControl
            Spacer(minLength: 8)
            Picker("Show", selection: $variantFilter) {
                Text("Light").tag(ThemeVariant.light)
                Text("Dark").tag(ThemeVariant.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .help("Show Light or Dark catalog variants.")
            .accessibilityIdentifier("settings.appearance.variantFilter")
        }
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

    /// Intrinsic-height stack, not a LazyVGrid. Lazy grids inside a
    /// GeometryReader ScrollView take the proposed viewport height as
    /// extra space after the first rows, which showed up as a black void
    /// between Nord Dark and the next card.
    private var catalogScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cardList
                useAsCustomControl
                if store.selection == .custom {
                    customTokenControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 4)
        }
    }

    private var cardList: some View {
        VStack(spacing: 12) {
            ForEach(ThemeFamily.allCases, id: \.self) { family in
                namedCard(family: family, variant: variantFilter)
            }
            customCard
        }
    }

    private func namedCard(family: ThemeFamily, variant: ThemeVariant) -> some View {
        let tokens = NamedThemeCatalog.tokens(for: family, variant: variant)
        return AppearanceThemeCard(
            title: family.displayName,
            tokens: tokens,
            isSelected: store.isShowing(family: family, variant: variant),
            onSelect: {
                rememberCloneSource(family, variant: variant)
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

    private var customCard: some View {
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

    private var useAsCustomControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Use as Custom") {
                requestUseAsCustom()
            }
            .disabled(cloneSourceTokens == nil)
            .accessibilityIdentifier("settings.appearance.useAsCustom")
            if let cloneSourceTitle {
                Text("Copies \(cloneSourceTitle) into Custom. Named themes stay unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Click a named theme first, then copy it into Custom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var customTokenControls: some View {
        let tokens = store.tokens(for: .custom)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Custom colors")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AppearanceTokenWell(title: "Background", color: tokens.background) {
                store.setCustomBackground($0)
            }
            AppearanceTokenWell(title: "Body", color: tokens.body) {
                store.setCustomBody($0)
            }
            DisclosureGroup("Headings", isExpanded: $headingsExpanded) {
                wellStack {
                    AppearanceTokenWell(title: "H1", color: tokens.h1) { store.setCustomH1($0) }
                    AppearanceTokenWell(title: "H2", color: tokens.h2) { store.setCustomH2($0) }
                    AppearanceTokenWell(title: "H3", color: tokens.h3) { store.setCustomH3($0) }
                    AppearanceTokenWell(title: "H4", color: tokens.h4) { store.setCustomH4($0) }
                    AppearanceTokenWell(title: "H5", color: tokens.h5) { store.setCustomH5($0) }
                    AppearanceTokenWell(title: "H6", color: tokens.h6) { store.setCustomH6($0) }
                }
            }
            DisclosureGroup("Emphasis", isExpanded: $emphasisExpanded) {
                wellStack {
                    AppearanceTokenWell(title: "Bold", color: tokens.bold) { store.setCustomBold($0) }
                    AppearanceTokenWell(title: "Italic", color: tokens.italic) { store.setCustomItalic($0) }
                    AppearanceTokenWell(title: "Bold-italic", color: tokens.boldItalic) { store.setCustomBoldItalic($0) }
                }
            }
            DisclosureGroup("Blocks", isExpanded: $blocksExpanded) {
                wellStack {
                    AppearanceTokenWell(title: "Links", color: tokens.link) { store.setCustomLink($0) }
                    AppearanceTokenWell(title: "Lists", color: tokens.list) { store.setCustomList($0) }
                    AppearanceTokenWell(title: "Fenced code", color: tokens.fence) { store.setCustomFence($0) }
                    AppearanceTokenWell(title: "Inline code", color: tokens.inlineCode) { store.setCustomInlineCode($0) }
                    AppearanceTokenWell(title: "Callouts", color: tokens.callout) { store.setCustomCallout($0) }
                    AppearanceTokenWell(title: "Tables", color: tokens.table) { store.setCustomTable($0) }
                }
            }
            DisclosureGroup("Other", isExpanded: $otherExpanded) {
                wellStack {
                    AppearanceTokenWell(title: "Strikethrough", color: tokens.strikethrough) { store.setCustomStrikethrough($0) }
                    AppearanceTokenWell(title: "Footnotes", color: tokens.footnote) { store.setCustomFootnote($0) }
                    AppearanceTokenWell(title: "Fold markers", color: tokens.foldMarker) { store.setCustomFoldMarker($0) }
                }
            }
        }
        .accessibilityIdentifier("settings.appearance.customControls")
    }

    private func wellStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(.top, 6)
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

    private func seedCloneSourceIfNeeded() {
        guard cloneFamily == nil, cloneVariant == nil else { return }
        if case .named(let family) = store.selection {
            cloneFamily = family
            cloneVariant = store.appliedVariant
        }
    }

    private func rememberCloneSource(_ family: ThemeFamily, variant: ThemeVariant) {
        cloneFamily = family
        cloneVariant = variant
    }

    private func requestUseAsCustom() {
        guard let cloneSourceTokens else { return }
        if store.customDiffers(from: cloneSourceTokens) {
            confirmReplaceCustom = true
        } else {
            applyClone()
        }
    }

    private func applyClone() {
        guard let cloneSourceTokens else { return }
        hoveredTokens = nil
        store.replaceCustom(with: cloneSourceTokens)
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

/// One custom selector. Writes are deferred so ColorPicker does not
/// publish ThemeStore changes during a SwiftUI view update.
private struct AppearanceTokenWell: View {
    let title: String
    let color: PlatformColorType
    let onChange: (PlatformColorType) -> Void

    var body: some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { Color(nsColor: color) },
                set: { newValue in
                    let picked = NSColor(newValue)
                    DispatchQueue.main.async { onChange(picked) }
                }
            )
        )
        .controlSize(.small)
    }
}
#endif

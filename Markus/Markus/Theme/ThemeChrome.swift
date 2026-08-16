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
    static func preview(_ selection: ThemeSelection?, on host: DocumentHost) {
        host.previewTheme(selection)
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
                    ForEach(NamedThemeID.allCases, id: \.self) { id in
                        ThemeCard(
                            title: id.displayName,
                            tokens: NamedThemeCatalog.tokens(for: id),
                            isSelected: host.themeStore.selection == .named(id)
                        ) {
                            ThemeChrome.select(.named(id), on: host)
                        } onHover: { hovering in
                            guard ThemeChrome.showsHoverPreview else { return }
                            ThemeChrome.preview(hovering ? .named(id) : nil, on: host)
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
                        ThemeChrome.preview(hovering ? .custom : nil, on: host)
                    }
                }
                if host.themeStore.selection == .custom {
                    customControls
                }
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker(
                "Background",
                selection: Binding(
                    get: { colorFromPlatform(host.themeStore.customBackground) },
                    set: { newValue in
                        host.setCustomBackground(platformColor(from: newValue))
                    }
                )
            )
            Picker("Text style", selection: Binding(
                get: { host.themeStore.customTextStyle },
                set: { host.setCustomTextStyle($0) }
            )) {
                Text("Auto").tag(CustomTextStyle.auto)
                Text("Light").tag(CustomTextStyle.light)
                Text("Dark").tag(CustomTextStyle.dark)
            }
            .pickerStyle(.segmented)
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

private struct ThemeCard: View {
    let title: String
    let tokens: ThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ThemeSampleView(tokens: tokens)
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

#if os(macOS)
private struct ThemeSampleView: NSViewRepresentable {
    var tokens: ThemeTokens

    func makeNSView(context: Context) -> FoldingTextView {
        let view = FoldingTextView()
        view.loadMarkdown(ThemeChrome.sampleMarkdown)
        view.setMode(.preview)
        view.setTheme(tokens)
        return view
    }

    func updateNSView(_ nsView: FoldingTextView, context: Context) {
        nsView.setTheme(tokens)
        nsView.ensureLayout()
    }
}
#else
private struct ThemeSampleView: UIViewRepresentable {
    var tokens: ThemeTokens

    func makeUIView(context: Context) -> FoldingTextView {
        let view = FoldingTextView()
        view.loadMarkdown(ThemeChrome.sampleMarkdown)
        view.setMode(.preview)
        view.setTheme(tokens)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: FoldingTextView, context: Context) {
        uiView.setTheme(tokens)
        uiView.ensureLayout()
    }
}
#endif

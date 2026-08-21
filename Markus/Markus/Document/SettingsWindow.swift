#if os(macOS)
import AppKit
import SwiftUI

/// Categories in the Preferences window's left-hand list. Separate from
/// `SettingsCategory` (the in-window takeover still uses Themes until
/// ticket 02 retires that surface).
enum SettingsWindowCategory: String, CaseIterable, Identifiable {
    case appearance
    case editor
    case about

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appearance: return "Appearance"
        case .editor: return "Editor"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: return "paintpalette"
        case .editor: return "textformat"
        case .about: return "info.circle"
        }
    }
}

/// Opens the SwiftUI `Settings` scene. Prefer `OpenSettingsAction` (the
/// macOS 14+ API). The gear lives in an `NSHostingController` document
/// window, so that environment value can be a no-op; in that case invoke
/// the Settings menu item SwiftUI already installed (⌘,), which is the
/// same path as **Markus → Settings…**. Do not send `showSettingsWindow:`
/// — that selector is not a valid AppKit API on macOS 14+.
enum SettingsWindowChrome {
    @MainActor
    static func open(_ openSettings: OpenSettingsAction) {
        openSettings()
        performInstalledSettingsMenuItem()
    }

    /// The live **Markus → Settings…** item, not a hard-coded selector.
    @MainActor
    static func performInstalledSettingsMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        let item = appMenu.items.first {
            $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
        }
        guard let item, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
}

/// Warp-style Preferences root: category list on the left, detail on the
/// right. Hosted by the macOS `Settings` scene so it is a separate window,
/// not a swap of the document viewport. An `HStack` split is used instead
/// of `NavigationSplitView` so the sidebar cannot collapse (Architecture
/// component 1). Appearance / Editor / About details are placeholders
/// until later tickets fill them.
struct SettingsWindowView: View {
    @State private var selectedCategory: SettingsWindowCategory = .appearance

    var body: some View {
        HStack(spacing: 0) {
            categoryList
                .frame(width: 200)
            Divider()
            SettingsWindowDetail(category: selectedCategory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension SettingsWindowView {
    var categoryList: some View {
        List(SettingsWindowCategory.allCases) { category in
            Button {
                selectedCategory = category
            } label: {
                Label(category.displayName, systemImage: category.symbolName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                selectedCategory == category
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
            .foregroundStyle(Color.primary)
            .accessibilityIdentifier("settings.window.category." + category.rawValue)
        }
        .listStyle(.sidebar)
    }
}

private struct SettingsWindowDetail: View {
    let category: SettingsWindowCategory

    var body: some View {
        switch category {
        case .appearance:
            placeholder(title: "Appearance", symbolName: "paintpalette")
        case .editor:
            placeholder(title: "Editor", symbolName: "textformat")
        case .about:
            placeholder(title: "About", symbolName: "info.circle")
        }
    }

    private func placeholder(title: String, symbolName: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbolName)
        } description: {
            Text("This page will be filled in a later ticket.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

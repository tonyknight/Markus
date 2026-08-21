#if os(macOS)
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
                    ? Color(nsColor: .selectedContentBackgroundColor)
                    : Color.clear
            )
            .foregroundStyle(
                selectedCategory == category
                    ? Color(nsColor: .alternateSelectedControlTextColor)
                    : Color.primary
            )
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

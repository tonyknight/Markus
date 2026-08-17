import SwiftUI

/// Categories shown in the settings surface's left-hand list. Only one
/// exists today (Themes, hosting the existing `ThemePickerView`); more
/// are expected to land in later tickets. Kept unguarded (not
/// `#if os(macOS)`) even though only the macOS-only `SettingsScene` view
/// reads it today, matching `LibraryChrome`'s precedent of leaving pure
/// data/logic cross-platform testable.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case themes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .themes: return "Themes"
        }
    }

    var symbolName: String {
        switch self {
        case .themes: return "paintpalette"
        }
    }
}

/// Pure logic behind the settings surface's close box, kept out of the
/// view body so dismissal is directly testable without rendering
/// SwiftUI (matching `LibraryChrome`'s precedent). The old side panel's
/// bug was a `ToolbarItem` inside a nested `NavigationStack` getting
/// hoisted into the window toolbar and becoming unreachable; routing the
/// close action through a plain function called from a plain button —
/// never a toolbar — avoids that failure mode entirely.
enum SettingsChrome {
    enum Identifier {
        static let close = "settings.close"
        static let categoryRowPrefix = "settings.category."
    }
}

#if os(macOS)
/// A full-viewport settings surface: a category list on the left, the
/// active category's detail on the right. Presented by `ContentView` as
/// a sibling of the document `NavigationStack` — never nested inside it
/// — whenever `host.isSettingsPresented` is true, so it replaces the
/// whole window content rather than appending a column next to the
/// editor (R7; Architecture component 5). The close box lands in T02.
struct SettingsScene: View {
    @ObservedObject var host: DocumentHost
    @State private var selectedCategory: SettingsCategory = .themes

    var body: some View {
        HStack(spacing: 0) {
            categoryList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var categoryList: some View {
        List(SettingsCategory.allCases) { category in
            Button {
                selectedCategory = category
            } label: {
                Label(category.displayName, systemImage: category.symbolName)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(SettingsChrome.Identifier.categoryRowPrefix + category.rawValue)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedCategory {
        case .themes:
            ThemePickerView(host: host)
        }
    }
}
#endif

import SwiftUI

/// Stable accessibility identifiers for the ribbon rail's two buttons.
enum RibbonRailChrome {
    enum Identifier {
        static let hamburger = "ribbon.hamburger"
        static let gear = "ribbon.gear"
    }
}

/// Pure logic behind the library panel's empty state, kept out of the
/// view body so it is testable without rendering SwiftUI. Opening one
/// file only grants a security scope for that file — its parent folder
/// cannot be enumerated under the sandbox (N7) — so there is no
/// "show the containing folder" fallback here, only Open Folder….
enum LibraryChrome {
    @MainActor
    static func openFolderFromEmptyState(on host: DocumentHost) {
        host.isFolderImporterPresented = true
    }
}

#if os(macOS)
/// A slim vertical rail pinned to the left of the document: a hamburger
/// at the top toggles the library panel (the relocated folder tree from
/// ticket 03), and a gear at the bottom opens settings. Settings itself
/// is rebuilt properly in ticket 06 — the gear here only wires the entry
/// point that ticket 02 removed from the macOS title bar.
struct RibbonRailView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        VStack(spacing: 12) {
            Button {
                host.toggleLibraryPanel()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Library")
            .accessibilityIdentifier(RibbonRailChrome.Identifier.hamburger)

            Spacer()

            Button {
                host.presentSettings()
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(RibbonRailChrome.Identifier.gear)
        }
        .padding(.vertical, 12)
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The library panel behind the ribbon rail's hamburger: it *is* the
/// `FolderTreeView` from ticket 03 (unmodified, relocated here rather
/// than duplicated), given a home and a toggle affordance. Shown by
/// `ContentView` whenever `host.isLibraryPanelOpen` is true. With no
/// folder session (e.g. a single file open, or the panel opened before
/// any folder was ever chosen) it falls back to an empty state instead
/// of a blank column.
struct LibraryPanelView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        if host.folderSession != nil {
            FolderTreeView(host: host)
        } else {
            LibraryEmptyStateView(host: host)
        }
    }
}

/// Shown in place of the tree when the library panel is open but no
/// folder session exists yet. Offers **Open Folder…** rather than
/// silently doing nothing.
struct LibraryEmptyStateView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        ContentUnavailableView {
            Label("No Folder Open", systemImage: "folder")
        } description: {
            Text("Open a folder to browse its Markdown files.")
        } actions: {
            Button("Open Folder…") {
                LibraryChrome.openFolderFromEmptyState(on: host)
            }
        }
    }
}
#endif

import SwiftUI

/// Stable accessibility identifiers for the ribbon rail's two buttons.
enum RibbonRailChrome {
    enum Identifier {
        static let hamburger = "ribbon.hamburger"
        static let gear = "ribbon.gear"
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
/// `ContentView` whenever `host.isLibraryPanelOpen` is true.
struct LibraryPanelView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        FolderTreeView(host: host)
    }
}
#endif

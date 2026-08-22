import SwiftUI

enum ModeChrome {
    enum MacItemPlacement: Equatable {
        case principal
    }

    enum IOSItemPlacement: Equatable {
        case navigationBar
    }

    static var showsMacTitleBarControl: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var showsIOSSegmentedControl: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    static let macItemPlacement: MacItemPlacement = .principal
    static let iosItemPlacement: IOSItemPlacement = .navigationBar

    #if os(macOS)
    static var macToolbarPlacement: ToolbarItemPlacement {
        switch macItemPlacement {
        case .principal:
            return .principal
        }
    }
    #endif

    #if os(iOS)
    static var iosToolbarPlacement: ToolbarItemPlacement {
        switch iosItemPlacement {
        case .navigationBar:
            return .principal
        }
    }
    #endif

    @MainActor
    static func select(_ mode: EditorMode, on host: DocumentHost) {
        guard host.session.kind.showsPreview || mode == .source else { return }
        host.setMode(mode)
    }
}

struct DocumentModePicker: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { host.mode },
            set: { newMode in
                // SwiftUI invokes this synchronously as part of its own
                // view-update transaction for the segmented control.
                // `ModeChrome.select` → `host.setMode` publishes
                // `objectWillChange` up through `DocumentSession`/
                // `DocumentHost` — doing that synchronously from inside a
                // Binding.set triggers "Publishing changes from within
                // view updates is not allowed" and the state change can
                // be silently dropped, which is why picking "Source"
                // appeared to do nothing. Deferring to the next run-loop
                // turn lets SwiftUI's current update transaction finish
                // first. (`ModeChrome.select` itself stays synchronous —
                // tests and other non-UI callers depend on that.)
                DispatchQueue.main.async {
                    ModeChrome.select(newMode, on: host)
                }
            }
        )) {
            Text("Source").tag(EditorMode.source)
            Text("Preview").tag(EditorMode.preview)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Editor mode")
        .accessibilityIdentifier(ToolbarChrome.Identifier.mode)
    }
}

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
        host.setMode(mode)
    }
}

struct DocumentModePicker: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { host.mode },
            set: { ModeChrome.select($0, on: host) }
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

#if os(macOS)
import AppKit
import SwiftUI

/// Categories in the Preferences window's left-hand list.
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

/// Opens the Preferences window (gear, **Markus → Settings…**, ⌘,).
/// Hosted as a SwiftUI `Window`, not a `Settings` scene — Settings is a
/// non-resizable panel and never shows edge handles.
enum SettingsWindowChrome {
    static let windowID = "markus-settings"

    @MainActor
    static func open(_ openWindow: OpenWindowAction) {
        openWindow(id: windowID)
    }

    @MainActor
    static func applyWindowPolicy(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(windowID)
        window.isRestorable = false
    }

    @MainActor
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == windowID { return true }
        return window.title == "Settings" && window.windowController == nil
    }

    /// Close Settings if SwiftUI presented it as the primary scene at
    /// launch. Menu / gear / ⌘, still call `open`.
    @MainActor
    static func closeIfUnsolicited() {
        for window in NSApp.windows where isSettingsWindow(window) {
            window.close()
        }
    }
}

/// Warp-style Preferences root: category list on the left, detail on the
/// right. Hosted by a resizable `Window` so it is separate from the
/// document viewport. An `HStack` split is used instead of
/// `NavigationSplitView` so the sidebar cannot collapse (Architecture
/// component 1).
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowResizeHook())
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
            AppearanceSettingsView()
        case .editor:
            EditorSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

struct AboutSettingsView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Markus"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.2"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("settings.about.appName")

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.about.version")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("settings.about.view")
    }
}

struct EditorSettingsView: View {
    @AppStorage(EditorSettings.defaultModeKey) private var defaultMode: EditorMode = .preview

    var body: some View {
        Form {
            Section {
                Picker("Default open mode:", selection: $defaultMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.editor.defaultMode")
            } header: {
                Text("Document Defaults")
            } footer: {
                Text("Applied to untitled and newly opened documents. Open windows are not affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("settings.editor.view")
    }
}

/// SwiftUI can still pin a Window to its content size after the first
/// layout. Re-assert `.resizable` on the real `NSWindow` so edge handles
/// and Zoom stay available.
private struct SettingsWindowResizeHook: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowResizeHookView {
        SettingsWindowResizeHookView()
    }

    func updateNSView(_ nsView: SettingsWindowResizeHookView, context: Context) {
        nsView.enableResize()
    }
}

private final class SettingsWindowResizeHookView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enableResize()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        enableResize()
    }

    func enableResize() {
        guard let window else { return }
        SettingsWindowChrome.applyWindowPolicy(window)
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        let minimum = NSSize(width: 720, height: 480)
        let maximum = NSSize(width: 10_000, height: 10_000)
        window.minSize = minimum
        window.maxSize = maximum
        window.contentMinSize = minimum
        window.contentMaxSize = maximum
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }
}
#endif

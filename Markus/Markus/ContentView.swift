import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        #if os(macOS)
        // The settings surface fills the entire viewport as a sibling of
        // the document `NavigationStack`, never nested inside it (R7) —
        // the old side panel's bug was a nested `NavigationStack`'s
        // toolbar item getting hoisted into the window toolbar.
        if host.isSettingsPresented {
            SettingsScene(host: host)
        } else {
            documentScene
        }
        #else
        documentScene
        #endif
    }

    private var documentScene: some View {
        NavigationStack {
            documentChrome
                .navigationTitle(host.session.fileURL?.lastPathComponent ?? host.folderSession?.rootURL.lastPathComponent ?? "Markus")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { DocumentToolbar(host: host) }
                .fileImporter(
                    isPresented: Binding(
                        get: { FileImporterChrome.isPresented(for: host) },
                        set: { FileImporterChrome.setPresented($0, on: host) }
                    ),
                    allowedContentTypes: FileImporterChrome.allowedContentTypes(for: host),
                    allowsMultipleSelection: false
                ) { [isFolder = host.isFolderImporterPresented] result in
                    // Captured at closure-creation time (this render pass),
                    // not read fresh from `host` inside `handle` — the
                    // `isPresented` binding's own `set(false)` and this
                    // completion handler both fire on dismissal, in an
                    // order SwiftUI doesn't guarantee, so reading the
                    // published flag *inside* the completion handler could
                    // already see it cleared and mislabel a folder-open
                    // failure as a file-open failure (or vice versa).
                    FileImporterChrome.handle(result, isFolder: isFolder, on: host)
                }
                .modifier(SettingsSheetModifier(host: host))
                .sheet(isPresented: $host.isOutlinePresented) {
                    OutlineSheet(host: host)
                }
                .sheet(isPresented: $host.isFindPresented) {
                    FindReplaceSheet(host: host)
                }
                .sheet(isPresented: $host.isGoToLinePresented) {
                    GoToLineSheet(host: host)
                }
                .alert("Open Failed", isPresented: Binding(
                    get: { host.errorMessage != nil },
                    set: { if !$0 { host.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { host.errorMessage = nil }
                } message: {
                    Text(host.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var documentChrome: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            RibbonRailView(host: host)
            if host.isLibraryPanelOpen {
                LibraryPanelView(host: host)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            }
            #else
            if FolderChrome.showsTree(for: host) {
                FolderTreeView(host: host)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            }
            #endif
            editorColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorColumn: some View {
        VStack(spacing: 0) {
            if !host.showsEditor {
                ContentUnavailableView {
                    Label("Markus", systemImage: "doc.plaintext")
                } description: {
                    Text("Open a Markdown file to preview it.")
                }
            } else {
                HStack(spacing: 0) {
                    SessionEditorRepresentable(session: host.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    if MacOnlyChrome.hasMinimapInChrome {
                        MacMinimapRepresentable(editor: host.session.editor)
                            .frame(width: 72)
                    }
                    #endif
                }
                EditorStatusBar(host: host)
            }
        }
    }
}

private struct DocumentToolbar: ToolbarContent {
    @ObservedObject var host: DocumentHost

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: ModeChrome.macToolbarPlacement) {
            DocumentModePicker(host: host)
        }
        #endif
        #if os(iOS)
        ToolbarItem(placement: ModeChrome.iosToolbarPlacement) {
            DocumentModePicker(host: host)
        }
        ToolbarItemGroup(placement: .automatic) {
            Button("Open") { host.isImporterPresented = true }
                .accessibilityIdentifier(ToolbarChrome.Identifier.open)
            Button("Open Folder") { host.isFolderImporterPresented = true }
                .accessibilityIdentifier(ToolbarChrome.Identifier.openFolder)
            Button("Save") { host.save() }
                .disabled(!host.canSave)
                .accessibilityIdentifier(ToolbarChrome.Identifier.save)
            Button("Revert") { host.revert() }
                .disabled(host.session.fileURL == nil || !host.session.isDirty)
                .accessibilityIdentifier(ToolbarChrome.Identifier.revert)
        }
        ToolbarItem(placement: .automatic) {
            Button("Fold") { EditorCommands.foldCurrent(on: host) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .accessibilityIdentifier(ToolbarChrome.Identifier.fold)
        }
        // Outline and Settings are iOS-only for now, matching the
        // ticket's Acceptance Criteria as written ("title bar contains
        // only the Source/Preview control" — an unconditional "only").
        // Neither has a macOS entry point yet (that's a later ticket's
        // ribbon rail / settings surface), but the AC carves out no
        // exception, so both wait on macOS until that entry point exists.
        ToolbarItem(placement: .automatic) {
            Menu("Outline") {
                Button("Show Outline") { EditorCommands.presentOutline(on: host) }
                if !host.outlineItems.isEmpty {
                    Divider()
                    ForEach(host.outlineItems, id: \.sourceLine) { item in
                        Button(item.title) { host.jumpToOutlineItem(item) }
                    }
                } else {
                    Text("No Headings")
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .accessibilityIdentifier(ToolbarChrome.Identifier.outline)
        }
        ToolbarItem(placement: .automatic) {
            Button("Toggle Mode") { EditorCommands.toggleSourcePreview(on: host) }
                .keyboardShortcut("e", modifiers: [.command])
                .accessibilityLabel("Toggle Source Preview")
                .accessibilityIdentifier(ToolbarChrome.Identifier.toggleMode)
        }
        ToolbarItemGroup(placement: .automatic) {
            Button("Find") { EditorCommands.presentFind(on: host) }
                .keyboardShortcut("f", modifiers: [.command])
                .accessibilityIdentifier(ToolbarChrome.Identifier.find)
            Button("Go to Line") { EditorCommands.presentGoToLine(on: host) }
                .keyboardShortcut("l", modifiers: [.command])
                .accessibilityIdentifier(ToolbarChrome.Identifier.goToLine)
            Button("Tree") { EditorCommands.focusTree(on: host) }
                .keyboardShortcut("1", modifiers: [.command])
                .accessibilityIdentifier(ToolbarChrome.Identifier.tree)
        }
        ToolbarItemGroup(placement: .automatic) {
            Button("Settings") { host.isSettingsPresented = true }
                .accessibilityIdentifier(ToolbarChrome.Identifier.settings)
            Menu("Recents") {
                if host.recents.items.isEmpty {
                    Text("No Recents")
                } else {
                    ForEach(host.recents.items, id: \.url) { item in
                        Button(item.isFolder ? item.url.lastPathComponent + "/" : item.url.lastPathComponent) {
                            host.openRecent(item)
                        }
                    }
                }
            }
            .accessibilityIdentifier(ToolbarChrome.Identifier.recents)
        }
        #endif
    }
}

/// Stable accessibility identifiers for `DocumentToolbar`'s items, used by
/// tests to inspect the real `NSToolbar` this SwiftUI toolbar materializes
/// into on macOS, rather than a compile-time platform flag.
enum ToolbarChrome {
    enum Identifier {
        static let mode = "toolbar.mode"
        static let open = "toolbar.open"
        static let openFolder = "toolbar.openFolder"
        static let save = "toolbar.save"
        static let revert = "toolbar.revert"
        static let fold = "toolbar.fold"
        static let outline = "toolbar.outline"
        static let toggleMode = "toolbar.toggleMode"
        static let find = "toolbar.find"
        static let goToLine = "toolbar.goToLine"
        static let tree = "toolbar.tree"
        static let settings = "toolbar.settings"
        static let recents = "toolbar.recents"
    }
}

private struct FindReplaceSheet: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        NavigationStack {
            Form {
                TextField("Find", text: $host.findQuery)
                TextField("Replace", text: $host.replaceText)
            }
            .navigationTitle("Find & Replace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { host.isFindPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find") { _ = host.findFromChrome(host.findQuery) }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Replace") { _ = host.replaceFromChrome(host.replaceText) }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 160)
    }
}

private struct GoToLineSheet: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        NavigationStack {
            Form {
                TextField("Line", text: $host.goToLineText)
            }
            .navigationTitle("Go to Line")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { host.isGoToLinePresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") { host.confirmGoToLineFromField() }
                }
            }
        }
        .frame(minWidth: 280, minHeight: 120)
    }
}

private struct OutlineSheet: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        NavigationStack {
            List(host.outlineItems, id: \.sourceLine) { item in
                Button(item.title) {
                    host.jumpToOutlineItem(item)
                    host.isOutlinePresented = false
                }
            }
            .navigationTitle("Outline")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { host.isOutlinePresented = false }
                }
            }
        }
    }
}

#if os(macOS)
struct SessionEditorRepresentable: NSViewRepresentable {
    var session: DocumentSession

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let view = session.editor
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width]
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = session.editor
        view.ensureLayout()
        let width = max(scroll.contentSize.width, 1)
        let height = max(scroll.contentSize.height, view.layoutHeight)
        view.setFrameSize(NSSize(width: width, height: height))
    }
}
#else
struct SessionEditorRepresentable: UIViewRepresentable {
    var session: DocumentSession

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        let view = session.editor
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth]
        scroll.addSubview(view)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let view = session.editor
        view.ensureLayout()
        let width = max(scroll.bounds.width, 1)
        let height = max(scroll.bounds.height, view.layoutHeight)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        scroll.contentSize = view.frame.size
    }
}
#endif

#Preview {
    AppRootView()
}

// iOS-only settings sheet. This is a pre-existing, already-functional
// modal presentation (unrelated to the macOS side-panel bug this ticket
// fixes — a `.sheet` owns its own presentation context, so its
// `ToolbarItem` never gets hoisted into a window toolbar the way the old
// macOS side panel's did). macOS gets the new full-viewport
// `SettingsScene` instead (see `SettingsScene.swift`); per the "no new
// iPhone/iPad chrome" non-goal, iOS keeps this sheet unchanged.
private struct SettingsPane: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        NavigationStack {
            ThemePickerView(host: host)
                .navigationTitle("Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            host.isSettingsPresented = false
                        }
                    }
                }
        }
    }
}

private struct SettingsSheetModifier: ViewModifier {
    @ObservedObject var host: DocumentHost

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $host.isSettingsPresented) {
            SettingsPane(host: host)
        }
        #else
        content
        #endif
    }
}

struct EditorStatusBar: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        HStack(spacing: 12) {
            Text(host.statusText)
                .font(.caption)
                .monospacedDigit()
            Spacer()
            Button("−") {
                host.setZoomScale(host.session.editor.zoomScale / 1.2)
            }
            .keyboardShortcut("-", modifiers: [.command])
            Button("+") {
                host.setZoomScale(host.session.editor.zoomScale * 1.2)
            }
            .keyboardShortcut("=", modifiers: [.command])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

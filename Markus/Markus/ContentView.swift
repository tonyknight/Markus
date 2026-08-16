import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        NavigationStack {
            documentChrome
                .navigationTitle(host.session.fileURL?.lastPathComponent ?? host.folderSession?.rootURL.lastPathComponent ?? "Markus")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { DocumentToolbar(host: host) }
                .fileImporter(
                    isPresented: $host.isImporterPresented,
                    allowedContentTypes: Self.markdownTypes,
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            host.openStandaloneFile(url)
                        }
                    case .failure:
                        host.errorMessage = "Could not open file."
                    }
                }
                .fileImporter(
                    isPresented: $host.isFolderImporterPresented,
                    allowedContentTypes: FolderChrome.folderContentTypes,
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            host.openFolder(url)
                        }
                    case .failure:
                        host.errorMessage = "Could not open folder."
                    }
                }
                .modifier(SettingsSheetModifier(host: host))
                .sheet(isPresented: $host.isOutlinePresented) {
                    OutlineSheet(host: host)
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
            if FolderChrome.showsTree(for: host) {
                FolderTreeView(host: host)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            }
            editorColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !ThemeChrome.presentsSettingsAsModalSheet, host.isSettingsPresented {
                SettingsPane(host: host)
                    .frame(minWidth: 380, idealWidth: 400, maxWidth: 480)
            }
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

    private static var markdownTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return types
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
        #endif
        ToolbarItem(placement: .automatic) {
            Button("Open") { host.isImporterPresented = true }
        }
        ToolbarItem(placement: .automatic) {
            Button("Open Folder") { host.isFolderImporterPresented = true }
        }
        ToolbarItem(placement: .automatic) {
            Button("Save") { host.save() }
                .disabled(!host.canSave)
        }
        ToolbarItem(placement: .automatic) {
            Button("Revert") { host.revert() }
                .disabled(host.session.fileURL == nil || !host.session.isDirty)
        }
        ToolbarItem(placement: .automatic) {
            Button("Fold") { EditorCommands.foldCurrent(on: host) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
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
        }
        ToolbarItem(placement: .automatic) {
            Button("Toggle Mode") { EditorCommands.toggleSourcePreview(on: host) }
                .keyboardShortcut("e", modifiers: [.command])
                .accessibilityLabel("Toggle Source Preview")
        }
        ToolbarItem(placement: .automatic) {
            Button("Tree") { EditorCommands.focusTree(on: host) }
                .keyboardShortcut("1", modifiers: [.command])
        }
        ToolbarItemGroup(placement: .automatic) {
            Button("Settings") { host.isSettingsPresented = true }
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
        }
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

    func makeNSView(context: Context) -> FoldingTextView {
        let view = session.editor
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: FoldingTextView, context: Context) {
        nsView.ensureLayout()
    }
}
#else
struct SessionEditorRepresentable: UIViewRepresentable {
    var session: DocumentSession

    func makeUIView(context: Context) -> FoldingTextView {
        let view = session.editor
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }

    func updateUIView(_ uiView: FoldingTextView, context: Context) {
        uiView.ensureLayout()
    }
}
#endif

#Preview {
    AppRootView()
}

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
        if ThemeChrome.presentsSettingsAsModalSheet {
            content.sheet(isPresented: $host.isSettingsPresented) {
                SettingsPane(host: host)
            }
        } else {
            content
        }
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

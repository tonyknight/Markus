import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var host = DocumentHost()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if host.session.fileURL == nil {
                    ContentUnavailableView {
                        Label("Markus", systemImage: "doc.plaintext")
                    } description: {
                        Text("Open a Markdown file to preview it.")
                    }
                } else {
                    SessionEditorRepresentable(session: host.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(host.session.fileURL?.lastPathComponent ?? "Markus")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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
                Button("Open") {
                    host.isImporterPresented = true
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("Save") {
                    host.save()
                }
                .disabled(host.session.fileURL == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button("Revert") {
                    host.revert()
                }
                .disabled(host.session.fileURL == nil || !host.session.isDirty)
            }
            ToolbarItem(placement: .automatic) {
                Menu("Recents") {
                    if host.recents.items.isEmpty {
                        Text("No Recents")
                    } else {
                        ForEach(host.recents.items, id: \.url) { item in
                            Button(item.url.lastPathComponent) {
                                host.openRecent(item)
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $host.isImporterPresented,
            allowedContentTypes: Self.markdownTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    host.openPicked(url)
                }
            case .failure:
                host.errorMessage = "Could not open file."
            }
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

    private static var markdownTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return types
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
    ContentView()
}

#if os(macOS)
import AppKit
import SwiftUI

/// File → New type picker. A small panel centered on the screen
/// with a dropdown of shipped kinds. Default is Markdown.
enum NewDocumentKindPicker {
    @MainActor
    private static var panel: NSPanel?

    @MainActor
    static func present() {
        if let existing = panel {
            if existing.isVisible {
                existing.center()
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            existing.close()
            panel = nil
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "New Document"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let host = NSHostingController(
            rootView: NewDocumentKindPickerView(
                onCreate: { kind in
                    close()
                    // The picker was key. Creating the untitled in the
                    // same turn leaves the new window without key status
                    // and FoldingTextView never becomes first responder.
                    DispatchQueue.main.async {
                        _ = try? MacDocumentLaunch.openUntitledDocument(ofType: kind.typeName)
                    }
                },
                onCancel: { close() }
            )
        )
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentViewController = host
        panel.center()
        Self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private static func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

private struct NewDocumentKindPickerView: View {
    @State private var selectedKind: DocumentKind = .markdown
    let onCreate: (DocumentKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a document type")
                .font(.headline)
            Picker("Document type", selection: $selectedKind) {
                ForEach(DocumentKind.shipped, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("new-document-kind-picker")
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onCreate(selectedKind)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
#endif

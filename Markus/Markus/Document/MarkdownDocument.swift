#if os(macOS)
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument {
    nonisolated(unsafe) let session: DocumentSession
    nonisolated(unsafe) let host: DocumentHost

    var configuredTabbingMode: NSWindow.TabbingMode {
        MacDocumentChrome.windowTabbingMode
    }

    static let tabbingIdentifier = MacDocumentChrome.tabbingIdentifier

    nonisolated override init() {
        precondition(Thread.isMainThread)
        let session = MainActor.assumeIsolated { DocumentSession() }
        self.session = session
        self.host = MainActor.assumeIsolated { DocumentHost(session: session, recents: RecentDocuments()) }
        super.init()
        hasUndoManager = false
    }

    nonisolated override class var autosavesInPlace: Bool { true }

    nonisolated override func makeWindowControllers() {
        MainActor.assumeIsolated {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            MacDocumentChrome.applyPreferredTabbing(to: window)
            window.contentViewController = NSHostingController(rootView: ContentView(host: host))
            window.title = fileURL?.lastPathComponent ?? session.fileURL?.lastPathComponent ?? "Untitled"
            addWindowController(NSWindowController(window: window))
        }
    }

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            try session.open(url: url)
            host.objectWillChange.send()
        }
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        let data = MainActor.assumeIsolated {
            DocumentSave.writeUTF8(from: session.textStorage)
        }
        try data.write(to: url, options: .atomic)
    }

    nonisolated override func data(ofType typeName: String) throws -> Data {
        MainActor.assumeIsolated {
            DocumentSave.writeUTF8(from: session.textStorage)
        }
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw DocumentSessionError.unreadable
        }
        MainActor.assumeIsolated {
            session.editor.loadMarkdown(markdown)
            host.objectWillChange.send()
        }
    }
}

final class MarkusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
#endif

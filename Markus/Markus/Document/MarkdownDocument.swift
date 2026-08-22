#if os(macOS)
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum MacWindowGeometry {
    /// Three-quarters of `visibleFrame`'s width and height, pinned to the
    /// screen's top-left corner. AppKit's y-axis is bottom-up, so "pinned
    /// to the top" means the window's `maxY` matches the screen's `maxY`.
    static func windowFrame(forVisibleFrame visibleFrame: NSRect) -> NSRect {
        let width = visibleFrame.width * 0.50
        let height = visibleFrame.height * 0.60
        let x = visibleFrame.minX
        let y = visibleFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

final class MarkusDocumentController: NSDocumentController {
    override var defaultType: String? {
        DocumentKind.markdown.typeName
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        MarkdownDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        KindPin().resolvedKind(for: url).typeName
    }
}

enum MacDocumentLaunch {
    @MainActor
    static func openUntitledDocument() throws -> NSDocument {
        try openUntitledDocument(ofType: nil)
    }

    @MainActor
    static func openUntitledDocument(ofType typeName: String?) throws -> NSDocument {
        let controller = NSDocumentController.shared
        let type = typeName ?? controller.defaultType ?? DocumentKind.markdown.typeName
        let kind = DocumentKind.from(typeName: type)
        do {
            let document = try controller.makeUntitledDocument(ofType: type)
            controller.addDocument(document)
            (document as? MarkdownDocument)?.applyUntitledKind(kind)
            document.makeWindowControllers()
            document.showWindows()
            return document
        } catch {
            let document = MarkdownDocument()
            document.applyUntitledKind(kind)
            document.makeWindowControllers()
            controller.addDocument(document)
            document.showWindows()
            return document
        }
    }

    @MainActor
    static func openFile(_ url: URL) throws -> NSDocument {
        let controller = NSDocumentController.shared
        if let existing = controller.document(for: url) {
            existing.showWindows()
            return existing
        }
        let type = (try? controller.typeForContents(of: url)) ?? KindPin().resolvedKind(for: url).typeName
        do {
            let document = try controller.makeDocument(withContentsOf: url, ofType: type)
            controller.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            return document
        } catch {
            let document = MarkdownDocument()
            try document.read(from: url, ofType: type)
            document.fileURL = url
            document.fileType = type
            document.makeWindowControllers()
            controller.addDocument(document)
            document.showWindows()
            return document
        }
    }
}

/// Hosts `ContentView` as the window's `contentViewController`. AppKit
/// automatically splices a window's `contentViewController` into the
/// responder chain (between the content view and the window itself), so
/// this is where the Edit-menu and Open-Folder actions — built with
/// `target == nil` in `MacMainMenu` — resolve when this document's window
/// is key.
final class MarkdownDocumentViewController: NSHostingController<ContentView> {
    let host: DocumentHost

    init(host: DocumentHost) {
        self.host = host
        super.init(rootView: ContentView(host: host))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func performOpenFolder(_ sender: Any?) {
        host.isFolderImporterPresented = true
    }

    @objc func performFind(_ sender: Any?) {
        EditorCommands.presentFind(on: host)
    }

    @objc func performGoToLine(_ sender: Any?) {
        EditorCommands.presentGoToLine(on: host)
    }

    @objc func performFoldAll(_ sender: Any?) {
        EditorCommands.foldAll(on: host)
    }

    @objc func performUnfoldAll(_ sender: Any?) {
        EditorCommands.unfoldAll(on: host)
    }

    @objc func setDocumentKindMarkdown(_ sender: Any?) {
        host.setKind(.markdown)
    }

    @objc func setDocumentKindJSON(_ sender: Any?) {
        host.setKind(.json)
    }

    @objc func setDocumentKindHTML(_ sender: Any?) {
        host.setKind(.html)
    }

    @objc func setDocumentKindSVG(_ sender: Any?) {
        host.setKind(.svg)
    }

    @objc func setDocumentKindTOML(_ sender: Any?) {
        host.setKind(.toml)
    }

    @objc func setDocumentKindCSS(_ sender: Any?) {
        host.setKind(.css)
    }

    @objc func setDocumentKindJavaScript(_ sender: Any?) {
        host.setKind(.javascript)
    }

    @objc func setDocumentKindTypeScript(_ sender: Any?) {
        host.setKind(.typescript)
    }

    @objc func setDocumentKindSwift(_ sender: Any?) {
        host.setKind(.swift)
    }

    @objc func setDocumentKindPHP(_ sender: Any?) {
        host.setKind(.php)
    }

    @objc func setDocumentKindShell(_ sender: Any?) {
        host.setKind(.shell)
    }

    @objc func pinDocumentKind(_ sender: Any?) {
        host.pinKind()
    }

    @objc func unpinDocumentKind(_ sender: Any?) {
        host.unpinKind()
    }
}

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
        self.host = MainActor.assumeIsolated {
            // Shares the single app-scoped `ThemeStore` across every Mac
            // document/tab so a theme change broadcasts to all of them
            // (R9; J.27) — the old per-`DocumentHost` `ThemeStore()` here
            // let two tabs disagree on theme.
            DocumentHost(session: session, recents: RecentDocuments(), themeStore: ThemeStore.shared)
        }
        super.init()
        hasUndoManager = false
        MainActor.assumeIsolated {
            // `loadMarkdown` is "the single place text-derived state is
            // rebuilt" (`FoldingSession.reparse` — `blocks`, `SourceMap`,
            // `UTF16LineOffsets`, everything caret placement, click
            // hit-testing, and the gutter depend on). `read(from:ofType:)`
            // calls it for an opened file via `session.open(url:)`, but a
            // brand-new untitled document (`NSDocumentController
            // .makeUntitledDocument`) never goes through `read` at all —
            // it just sits with those caches at their default empty/nil
            // state indefinitely. That's why new documents couldn't be
            // typed into: Source mode's caret/click geometry had nothing
            // to resolve against. Loading empty content here reparses
            // once, unconditionally, so a new document starts in the same
            // state an opened one reaches via `read` — redundant (and
            // immediately overwritten) for the opened-file case, since
            // `read` runs right after this and reparses again with the
            // real content, but harmless and not worth special-casing.
            self.session.editor.loadMarkdown("")
            self.host.attachMacDocument(self)
            // T04: the second callback the ticket's Design note calls
            // for, alongside `onTextDidChange` — every committed text
            // mutation (insertText/backspace/delete/undo/redo, and the
            // pre-ticket `insertTextAtCaret`/`replaceSelection`
            // helpers) reports its kind via real `UndoManager
            // .isUndoing`/`.isRedoing` state at commit time
            // (`FoldingTextView.currentTextChangeKind`), so this only
            // has to map that kind onto the matching
            // `NSDocument.ChangeType` (R21).
            self.session.editor.onTextChangeCommitted = { [weak self] kind in
                guard let self else { return }
                switch kind {
                case .done: self.updateChangeCount(.changeDone)
                case .undone: self.updateChangeCount(.changeUndone)
                case .redone: self.updateChangeCount(.changeRedone)
                }
            }
        }
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
            window.contentViewController = MarkdownDocumentViewController(host: host)
            window.title = fileURL?.lastPathComponent ?? session.fileURL?.lastPathComponent ?? "Untitled"
            // Set geometry last: assigning contentViewController can trigger
            // NSHostingController's automatic content-size-driven window
            // resize, which would otherwise clobber this frame.
            let screen = window.screen ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                window.setFrame(MacWindowGeometry.windowFrame(forVisibleFrame: visibleFrame), display: false)
            }
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
        try MainActor.assumeIsolated {
            let data = DocumentSave.writeUTF8(from: session.textStorage)
            try data.write(to: url, options: .atomic)
            session.markSaved(at: url)
            updateChangeCount(.changeCleared)
        }
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
            session.markLoaded(markdown, kind: DocumentKind.from(typeName: typeName))
            session.editor.loadMarkdown(markdown)
            host.objectWillChange.send()
        }
    }

    @MainActor
    func applyUntitledKind(_ kind: DocumentKind) {
        fileType = kind.typeName
        session.setKind(kind)
    }

    nonisolated override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        MainActor.assumeIsolated {
            let current = fileType ?? session.kind.typeName
            let all = DocumentKind.shipped.map(\.typeName)
            return [current] + all.filter { $0 != current }
        }
    }

    nonisolated override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        DocumentKind.from(typeName: typeName).defaultExtension
    }
}

final class MarkusAppDelegate: NSObject, NSApplicationDelegate {
    private let documentController = MarkusDocumentController()

    // The File/Edit menu content lives in `MarkusCommands` (SwiftUI
    // `Commands`, attached via `.commands { }` on `MarkusApp`'s Settings
    // window scene), not here. An earlier version of this delegate imperatively
    // assigned `NSApp.mainMenu = MacMainMenu.build()` — that lost a race
    // against SwiftUI's own Scene/Commands machinery, which reinstalls
    // its own default menu at multiple points during and after launch,
    // silently replacing (not merging with) anything assigned here. See
    // `MarkusCommands`'s doc comment for the full story.

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        _ = documentController
        if documentController.documents.isEmpty {
            _ = try? MacDocumentLaunch.openUntitledDocument()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if !NSDocumentController.shared.documents.isEmpty {
            return true
        }
        return (try? MacDocumentLaunch.openUntitledDocument()) != nil
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where !url.hasDirectoryPath {
            _ = try? MacDocumentLaunch.openFile(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            return applicationOpenUntitledFile(sender)
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
#endif

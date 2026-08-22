import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class DocumentHost: ObservableObject {
    let session: DocumentSession
    let recents: RecentDocuments
    let themeStore: ThemeStore
    @Published var isImporterPresented = false
    @Published var isFolderImporterPresented = false
    @Published var isSettingsPresented = false
    @Published var isLibraryPanelOpen = false
    @Published var isOutlinePresented = false
    @Published var isFindPresented = false
    @Published var isGoToLinePresented = false
    @Published var isTreeFocused = false
    @Published var isTreeFocusConsumed = false
    @Published var findQuery = ""
    @Published var replaceText = ""
    @Published var goToLineText = ""
    @Published var errorMessage: String?
    private(set) var folderSession: FolderSession?
    private var sessionCancellable: AnyCancellable?
    private var themeCancellable: AnyCancellable?
    private var themeChangeCancellable: AnyCancellable?

    var isFolderTreeVisible: Bool {
        folderSession != nil
    }

    var showsEditor: Bool {
        #if os(macOS)
        true
        #else
        session.fileURL != nil
        #endif
    }

    var canSave: Bool {
        #if os(macOS)
        true
        #else
        session.fileURL != nil
        #endif
    }

    #if os(macOS)
    weak var macDocument: MarkdownDocument?

    func attachMacDocument(_ document: MarkdownDocument) {
        macDocument = document
    }
    #endif

    init() {
        self.session = DocumentSession()
        self.recents = RecentDocuments()
        self.themeStore = ThemeStore()
        observe()
        applyCommittedTheme()
    }

    init(session: DocumentSession, recents: RecentDocuments) {
        self.session = session
        self.recents = recents
        self.themeStore = ThemeStore()
        observe()
        applyCommittedTheme()
    }

    init(session: DocumentSession, recents: RecentDocuments, themeStore: ThemeStore) {
        self.session = session
        self.recents = recents
        self.themeStore = themeStore
        observe()
        applyCommittedTheme()
    }

    init(recents: RecentDocuments) {
        self.session = DocumentSession()
        self.recents = recents
        self.themeStore = ThemeStore()
        observe()
        applyCommittedTheme()
    }

    init(recents: RecentDocuments, themeStore: ThemeStore) {
        self.session = DocumentSession()
        self.recents = recents
        self.themeStore = themeStore
        observe()
        applyCommittedTheme()
    }

    private func observe() {
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        themeCancellable = themeStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Broadcasts a committed theme change (never a hover) from *any*
        // `DocumentHost` sharing this store to every other one, repainting
        // each one's own real editor — the mechanism that makes theme
        // selection app-scoped rather than per-window (R9; J.27).
        themeChangeCancellable = themeStore.themeChanged.sink { [weak self] _ in
            self?.applyCommittedTheme()
        }
    }

    func applyTheme(_ selection: ThemeSelection) {
        themeStore.select(selection)
    }

    func applyNamedTheme(_ family: ThemeFamily, variant: ThemeVariant) {
        themeStore.selectNamed(family, variant: variant)
    }

    /// iOS picker hover only (`ThemePickerView` → `displayedTokens`).
    /// Must never touch the real editor; the editor stays on
    /// `committedTokens` until `themeChanged` (N2). macOS Appearance
    /// hover is `@State` on that page and must not call this.
    func previewTheme(_ tokens: ThemeTokens?) {
        if let tokens {
            themeStore.beginHover(tokens)
        } else {
            themeStore.endHover()
        }
        objectWillChange.send()
    }

    func setCustomBackground(_ color: PlatformColorType) {
        themeStore.setCustomBackground(color)
    }

    func setCustomTextStyle(_ style: CustomTextStyle) {
        themeStore.setCustomTextStyle(style)
    }

    func setCustomHeading(_ color: PlatformColorType) {
        themeStore.setCustomHeading(color)
    }

    func setCustomBody(_ color: PlatformColorType) {
        themeStore.setCustomBody(color)
    }

    func setCustomLink(_ color: PlatformColorType) {
        themeStore.setCustomLink(color)
    }

    func setCustomFence(_ color: PlatformColorType) {
        themeStore.setCustomFence(color)
    }

    private func applyCommittedTheme() {
        session.editor.setTheme(themeStore.committedTokens)
        objectWillChange.send()
    }

    func openStandaloneFile(_ url: URL) {
        #if os(macOS)
        if MacDocumentChrome.standaloneFileOpenCreatesNewDocument {
            do {
                _ = try MacDocumentLaunch.openFile(url)
                recents.record(url: url)
                errorMessage = nil
                objectWillChange.send()
            } catch {
                errorMessage = "Could not open file."
            }
            return
        }
        #endif
        openPicked(url)
    }

    func openPicked(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            openFolder(url)
            return
        }
        do {
            try session.open(url: url)
            clearFolderSession()
            recents.record(url: url)
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = "Could not open file."
        }
    }

    func openFolder(_ url: URL, alreadyAccessing: Bool = false) {
        folderSession?.stopAccessing()
        folderSession = FolderSession(rootURL: url, alreadyAccessing: alreadyAccessing)
        recents.record(url: url, isFolder: true)
        errorMessage = nil
        // Opening a folder — via Open Folder… or Recents — is an explicit
        // request to see it, so the ribbon rail's library panel opens
        // automatically (it can still be closed manually afterward).
        isLibraryPanelOpen = true
        objectWillChange.send()
    }

    private func clearFolderSession() {
        folderSession?.stopAccessing()
        folderSession = nil
    }

    func openTreeFile(_ url: URL) {
        do {
            try session.open(url: url)
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = "Could not open file."
        }
    }

    func openRecent(_ item: RecentDocumentItem) {
        do {
            let url = try recents.startAccessing(item)
            if item.isFolder {
                openFolder(url, alreadyAccessing: true)
                recents.record(url: url, bookmarkData: item.bookmarkData, isFolder: true)
            } else {
                #if os(macOS)
                if MacDocumentChrome.standaloneFileOpenCreatesNewDocument {
                    _ = try MacDocumentLaunch.openFile(url)
                    recents.record(url: url, bookmarkData: item.bookmarkData)
                    recents.stopAccessing(url)
                    errorMessage = nil
                    objectWillChange.send()
                    return
                }
                #endif
                defer { recents.stopAccessing(url) }
                try session.open(url: url)
                clearFolderSession()
                recents.record(url: url, bookmarkData: item.bookmarkData)
            }
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = item.isFolder ? "Could not open recent folder." : "Could not open recent file."
        }
    }

    func save() {
        #if os(macOS)
        if let macDocument {
            if let url = macDocument.fileURL ?? session.fileURL {
                do {
                    try macDocument.write(to: url, ofType: macDocument.fileType ?? session.kind.typeName)
                    errorMessage = nil
                    objectWillChange.send()
                } catch {
                    errorMessage = "Could not save file."
                }
            } else {
                _ = NSApp.sendAction(#selector(NSDocument.save(_:)), to: macDocument, from: nil)
            }
            return
        }
        #endif
        do {
            try session.save()
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = "Could not save file."
        }
    }

    func revert() {
        do {
            try session.revert()
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = "Could not revert file."
        }
    }

    var mode: EditorMode {
        session.mode
    }

    func setMode(_ mode: EditorMode) {
        session.setMode(mode)
        objectWillChange.send()
    }

    func setKind(_ kind: DocumentKind) {
        session.setKind(kind)
        #if os(macOS)
        macDocument?.fileType = kind.typeName
        #endif
        objectWillChange.send()
    }

    func pinKind() {
        session.pinKind()
        objectWillChange.send()
    }

    func unpinKind() {
        session.unpinKind()
        #if os(macOS)
        macDocument?.fileType = session.kind.typeName
        #endif
        objectWillChange.send()
    }

    var outlineItems: [OutlineItem] {
        session.outlineItems
    }

    /// Parse diagnostics from the active profile (v1.4 data hook; no inspector UI).
    var diagnostics: [ParseDiagnostic] {
        session.diagnostics
    }

    func jumpToOutlineItem(_ item: OutlineItem) {
        session.editor.jumpToSourceLine(item.sourceLine)
        objectWillChange.send()
    }

    @discardableResult
    func find(_ query: String) -> NSRange? {
        session.editor.find(query)
    }

    @discardableResult
    func replaceSelection(with replacement: String) -> Bool {
        session.editor.replaceSelection(with: replacement)
    }

    func goToLine(_ line: Int) {
        session.editor.jumpToSourceLine(line)
        objectWillChange.send()
    }

    var statusSourceLine: Int {
        if let y = session.editor.lastJumpedPackedY, let line = session.editor.sourceLine(atY: y) {
            return line
        }
        return 1
    }

    var statusText: String {
        let modeLabel = mode == .source ? "Source" : "Preview"
        let dirty = session.isDirty ? " •" : ""
        return "Line \(statusSourceLine)  \(modeLabel)\(dirty)"
    }

    func setZoomScale(_ scale: CGFloat) {
        session.editor.setZoomScale(scale)
        objectWillChange.send()
    }

    func presentOutline() {
        isOutlinePresented = true
        objectWillChange.send()
    }

    func presentSettings() {
        isSettingsPresented = true
        objectWillChange.send()
    }

    /// Toggles the left ribbon rail's library panel (macOS-only chrome).
    /// The panel starts closed; the hamburger flips this regardless of
    /// whether a folder session exists — `LibraryPanelView` decides
    /// whether to show the tree or an empty state for that case.
    func toggleLibraryPanel() {
        isLibraryPanelOpen.toggle()
        objectWillChange.send()
    }

    func toggleSourcePreview() {
        setMode(mode == .source ? .preview : .source)
    }

    func presentFind() {
        isFindPresented = true
        objectWillChange.send()
    }

    @discardableResult
    func findFromChrome(_ query: String) -> NSRange? {
        findQuery = query
        return find(query)
    }

    @discardableResult
    func replaceFromChrome(_ replacement: String) -> Bool {
        replaceText = replacement
        return replaceSelection(with: replacement)
    }

    func presentGoToLine() {
        isGoToLinePresented = true
        objectWillChange.send()
    }

    func confirmGoToLine(_ line: Int) {
        goToLine(line)
        isGoToLinePresented = false
        objectWillChange.send()
    }

    func confirmGoToLineFromField() {
        let trimmed = goToLineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let line = Int(trimmed) {
            confirmGoToLine(line)
        }
    }

    func markTreeFocusConsumed() {
        guard isFolderTreeVisible, isTreeFocused else { return }
        isTreeFocusConsumed = true
        objectWillChange.send()
    }

    func focusTree() {
        if folderSession == nil {
            isFolderImporterPresented = true
            isTreeFocused = false
            isTreeFocusConsumed = false
        } else {
            isTreeFocused = true
            isTreeFocusConsumed = false
        }
        objectWillChange.send()
    }

    func foldCurrent() {
        session.editor.foldCurrent()
        objectWillChange.send()
    }

    func foldAll() {
        session.editor.foldAll()
        objectWillChange.send()
    }

    func unfoldAll() {
        session.editor.unfoldAll()
        objectWillChange.send()
    }
}

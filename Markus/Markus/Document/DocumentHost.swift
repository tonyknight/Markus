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
    @Published var errorMessage: String?
    private(set) var folderSession: FolderSession?
    private var sessionCancellable: AnyCancellable?
    private var themeCancellable: AnyCancellable?

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
        applyDisplayedTheme()
    }

    init(session: DocumentSession, recents: RecentDocuments) {
        self.session = session
        self.recents = recents
        self.themeStore = ThemeStore()
        observe()
        applyDisplayedTheme()
    }

    init(session: DocumentSession, recents: RecentDocuments, themeStore: ThemeStore) {
        self.session = session
        self.recents = recents
        self.themeStore = themeStore
        observe()
        applyDisplayedTheme()
    }

    init(recents: RecentDocuments) {
        self.session = DocumentSession()
        self.recents = recents
        self.themeStore = ThemeStore()
        observe()
        applyDisplayedTheme()
    }

    init(recents: RecentDocuments, themeStore: ThemeStore) {
        self.session = DocumentSession()
        self.recents = recents
        self.themeStore = themeStore
        observe()
        applyDisplayedTheme()
    }

    private func observe() {
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        themeCancellable = themeStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func applyTheme(_ selection: ThemeSelection) {
        themeStore.select(selection)
        applyDisplayedTheme()
    }

    func previewTheme(_ selection: ThemeSelection?) {
        if let selection {
            themeStore.beginHover(selection)
        } else {
            themeStore.endHover()
        }
        applyDisplayedTheme()
    }

    func setCustomBackground(_ color: PlatformColorType) {
        themeStore.setCustomBackground(color)
        applyDisplayedTheme()
    }

    func setCustomTextStyle(_ style: CustomTextStyle) {
        themeStore.setCustomTextStyle(style)
        applyDisplayedTheme()
    }

    private func applyDisplayedTheme() {
        session.editor.setTheme(themeStore.displayedTokens)
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
                    try macDocument.write(to: url, ofType: macDocument.fileType ?? "net.daringfireball.markdown")
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
}

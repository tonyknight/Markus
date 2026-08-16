import Combine
import Foundation

@MainActor
final class DocumentHost: ObservableObject {
    let session: DocumentSession
    let recents: RecentDocuments
    @Published var isImporterPresented = false
    @Published var isFolderImporterPresented = false
    @Published var errorMessage: String?
    private(set) var folderSession: FolderSession?
    private var sessionCancellable: AnyCancellable?

    var isFolderTreeVisible: Bool {
        folderSession != nil
    }

    init() {
        self.session = DocumentSession()
        self.recents = RecentDocuments()
        observeSession()
    }

    init(session: DocumentSession, recents: RecentDocuments) {
        self.session = session
        self.recents = recents
        observeSession()
    }

    init(recents: RecentDocuments) {
        self.session = DocumentSession()
        self.recents = recents
        observeSession()
    }

    private func observeSession() {
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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

import Combine
import Foundation

@MainActor
final class DocumentHost: ObservableObject {
    let session: DocumentSession
    let recents: RecentDocuments
    @Published var isImporterPresented = false
    @Published var errorMessage: String?
    private var sessionCancellable: AnyCancellable?

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
        do {
            try session.open(url: url)
            recents.record(url: url)
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = "Could not open file."
        }
    }

    func openRecent(_ item: RecentDocumentItem) {
        do {
            let url = try recents.startAccessing(item)
            defer { recents.stopAccessing(url) }
            try session.open(url: url)
            recents.record(url: url, bookmarkData: item.bookmarkData)
            errorMessage = nil
            objectWillChange.send()
        } catch {
            errorMessage = "Could not open recent file."
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

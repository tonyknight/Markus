import Combine
import Foundation

@MainActor
final class DocumentHost: ObservableObject {
    let session: DocumentSession
    let recents: RecentDocuments
    @Published var isImporterPresented = false
    @Published var errorMessage: String?

    init() {
        self.session = DocumentSession()
        self.recents = RecentDocuments()
    }

    init(session: DocumentSession, recents: RecentDocuments) {
        self.session = session
        self.recents = recents
    }

    init(recents: RecentDocuments) {
        self.session = DocumentSession()
        self.recents = recents
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
}

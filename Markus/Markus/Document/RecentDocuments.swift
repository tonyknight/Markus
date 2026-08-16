import Foundation

struct RecentDocumentItem: Codable, Equatable {
    var url: URL
    var bookmarkData: Data?
}

enum RecentDocumentsError: Error, Equatable {
    case staleBookmark
}

final class RecentDocuments {
    static let storageKey = "markus.recentDocuments"

    private let defaults: UserDefaults
    private let limit = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var items: [RecentDocumentItem] {
        load()
    }

    func record(url: URL, bookmarkData: Data? = nil) {
        var data = bookmarkData
        #if os(iOS)
        if data == nil {
            data = try? url.bookmarkData(options: .minimalBookmark)
        }
        #endif
        let standardized = url.standardizedFileURL
        var next = load().filter { $0.url.standardizedFileURL != standardized }
        next.insert(RecentDocumentItem(url: url, bookmarkData: data), at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        save(next)
    }

    func startAccessing(_ item: RecentDocumentItem) throws -> URL {
        guard let bookmark = item.bookmarkData else {
            return item.url
        }
        var isStale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw RecentDocumentsError.staleBookmark
        }
        if isStale {
            throw RecentDocumentsError.staleBookmark
        }
        let accessed = resolved.startAccessingSecurityScopedResource()
        #if os(iOS)
        guard accessed else {
            throw RecentDocumentsError.staleBookmark
        }
        #else
        _ = accessed
        #endif
        return resolved
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    private func load() -> [RecentDocumentItem] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([RecentDocumentItem].self, from: data)) ?? []
    }

    private func save(_ items: [RecentDocumentItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

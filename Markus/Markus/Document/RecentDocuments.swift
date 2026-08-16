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
        if data == nil {
            data = try? Self.makeBookmark(for: url)
        }
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
            resolved = try Self.resolveBookmark(bookmark, isStale: &isStale)
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

    private static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        .minimalBookmark
        #endif
    }

    private static func resolveBookmark(_ bookmark: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
        do {
            return try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
        #else
        return try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
    }
}

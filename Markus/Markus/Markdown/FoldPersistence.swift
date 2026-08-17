import Foundation

/// Per-file fold persistence in app storage (R16), following the same
/// `UserDefaults`-backed pattern as `RecentDocuments` and `ThemeStore`:
/// one JSON blob under a single key, keyed internally by file path.
final class FoldPersistence {
    static let storageKey = "markus.folds"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for url: URL) -> Set<FoldID> {
        Set(loadAll()[Self.key(for: url)] ?? [])
    }

    func save(_ ids: Set<FoldID>, for url: URL) {
        var all = loadAll()
        all[Self.key(for: url)] = Array(ids)
        persist(all)
    }

    private func loadAll() -> [String: [FoldID]] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [FoldID]].self, from: data)) ?? [:]
    }

    private func persist(_ all: [String: [FoldID]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

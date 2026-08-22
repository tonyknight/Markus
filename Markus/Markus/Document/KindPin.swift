import Foundation

/// Per-file document-kind pin in app storage (R2), following the same
/// `UserDefaults`-backed pattern as `FoldPersistence`: one JSON blob
/// under a single key, keyed internally by file path.
///
/// A pin is stored only when the user explicitly pins. Untitled files
/// have no URL and must not be written here.
final class KindPin {
    static let storageKey = "markus.kindPins"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func kind(for url: URL) -> DocumentKind? {
        guard let raw = loadAll()[Self.key(for: url)] else { return nil }
        return DocumentKind(rawValue: raw)
    }

    /// Pin if present, otherwise UTI/extension map.
    func resolvedKind(for url: URL) -> DocumentKind {
        kind(for: url) ?? DocumentKind.from(url: url)
    }

    func set(_ kind: DocumentKind, for url: URL) {
        var all = loadAll()
        all[Self.key(for: url)] = kind.rawValue
        persist(all)
    }

    func remove(for url: URL) {
        var all = loadAll()
        all.removeValue(forKey: Self.key(for: url))
        persist(all)
    }

    private func loadAll() -> [String: String] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func persist(_ all: [String: String]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

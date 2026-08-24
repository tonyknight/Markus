import Foundation

struct FolderTreeNode: Equatable, Identifiable {
    var id: URL { url }
    var name: String
    var url: URL
    var isDirectory: Bool
    var children: [FolderTreeNode]
    var outlineChildren: [FolderTreeNode]? {
        isDirectory ? children : nil
    }
}

enum MarkdownFolderTree {
    static let markdownExtensions: Set<String> = Set(DocumentKind.markdown.filenameExtensions)

    static let shippedExtensions: Set<String> = Set(
        DocumentKind.shipped.flatMap(\.filenameExtensions)
    )

    /// Builds the folder tree rooted at `root`, listing shipped document
    /// kinds (Markdown plus JSON/HTML/SVG/TOML/Wave B).
    ///
    /// `listDirectoryContents` is how a directory's entries are obtained.
    /// It defaults to `defaultListDirectoryContents`, which enumerates via
    /// the **URL** (`FileManager.contentsOfDirectory(at:)`), never a path
    /// string. Under the App Sandbox a folder is only reachable through its
    /// security-scoped URL (see `Markus.entitlements`,
    /// `startAccessingSecurityScopedResource()`); path-based enumeration
    /// (`contentsOfDirectory(atPath:)`) is silently denied there (N7). The
    /// parameter exists so tests can prove the mechanism is exclusively
    /// URL-based without depending on live OS sandbox behavior.
    static func build(
        root: URL,
        listDirectoryContents: (URL) -> [URL] = defaultListDirectoryContents
    ) -> [FolderTreeNode] {
        children(of: root, listDirectoryContents: listDirectoryContents)
    }

    static func defaultListDirectoryContents(_ directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
    }

    private static func children(
        of directory: URL,
        listDirectoryContents: (URL) -> [URL]
    ) -> [FolderTreeNode] {
        let entries = listDirectoryContents(directory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var nodes: [FolderTreeNode] = []
        for url in entries {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            if isDirectory(url) {
                let nested = children(of: url, listDirectoryContents: listDirectoryContents)
                guard !nested.isEmpty else { continue }
                nodes.append(FolderTreeNode(name: name, url: url, isDirectory: true, children: nested))
            } else if isShippedDocumentFile(name) {
                nodes.append(FolderTreeNode(name: name, url: url, isDirectory: false, children: []))
            }
        }
        return nodes
    }

    /// Determines directory-ness purely from the URL: `resourceValues`
    /// (URL-based, never a path string) when the resource is reachable,
    /// falling back to the URL's own directory-path hint otherwise (e.g.
    /// for synthetic URLs in tests).
    private static func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           let isDir = values.isDirectory {
            return isDir
        }
        return url.hasDirectoryPath
    }

    private static func isShippedDocumentFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return shippedExtensions.contains(ext)
    }
}

import Foundation

@MainActor
final class FolderSession {
    let rootURL: URL
    private(set) var tree: [FolderTreeNode]
    private(set) var isAccessingRoot: Bool
    private var ownsAccess: Bool

    init(rootURL: URL, alreadyAccessing: Bool = false) {
        self.rootURL = rootURL
        if alreadyAccessing {
            ownsAccess = true
        } else {
            ownsAccess = rootURL.startAccessingSecurityScopedResource()
        }
        isAccessingRoot = true
        self.tree = MarkdownFolderTree.build(root: rootURL)
    }

    func stopAccessing() {
        if ownsAccess {
            rootURL.stopAccessingSecurityScopedResource()
            ownsAccess = false
        }
        isAccessingRoot = false
    }

    deinit {
        if ownsAccess {
            rootURL.stopAccessingSecurityScopedResource()
        }
    }
}

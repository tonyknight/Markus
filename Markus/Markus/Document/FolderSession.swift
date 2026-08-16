import Foundation

@MainActor
final class FolderSession {
    let rootURL: URL
    private(set) var tree: [FolderTreeNode]

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.tree = MarkdownFolderTree.build(root: rootURL)
    }
}

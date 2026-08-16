import Foundation

struct FolderTreeNode: Equatable, Identifiable {
    var id: URL { url }
    var name: String
    var url: URL
    var isDirectory: Bool
    var children: [FolderTreeNode]
}

enum MarkdownFolderTree {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    static func build(root: URL) -> [FolderTreeNode] {
        children(of: root)
    }

    private static func children(of directory: URL) -> [FolderTreeNode] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        var nodes: [FolderTreeNode] = []
        for name in names.sorted() {
            if name.hasPrefix(".") { continue }
            let url = directory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let nested = children(of: url)
                guard !nested.isEmpty else { continue }
                nodes.append(FolderTreeNode(name: name, url: url, isDirectory: true, children: nested))
            } else if isMarkdownFile(name) {
                nodes.append(FolderTreeNode(name: name, url: url, isDirectory: false, children: []))
            }
        }
        return nodes
    }

    private static func isMarkdownFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return markdownExtensions.contains(ext)
    }
}

import SwiftUI
import UniformTypeIdentifiers

enum FolderChrome {
    static var folderContentTypes: [UTType] { [.folder] }

    @MainActor
    static func showsTree(for host: DocumentHost) -> Bool {
        host.isFolderTreeVisible
    }
}

struct FolderTreeView: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        if FolderChrome.showsTree(for: host), let folder = host.folderSession {
            List {
                OutlineGroup(folder.tree, id: \.url, children: \.outlineChildren) { node in
                    if node.isDirectory {
                        Label(node.name, systemImage: "folder")
                    } else {
                        Button {
                            host.openTreeFile(node.url)
                        } label: {
                            Label(node.name, systemImage: "doc.plaintext")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

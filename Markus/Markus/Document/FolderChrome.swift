import SwiftUI
import UniformTypeIdentifiers

enum FolderChrome {
    static var folderContentTypes: [UTType] { [.folder] }

    @MainActor
    static func showsTree(for host: DocumentHost) -> Bool {
        host.isFolderTreeVisible
    }

    @MainActor
    static func consumeTreeFocus(_ host: DocumentHost) {
        guard showsTree(for: host), host.isTreeFocused else { return }
        host.markTreeFocusConsumed()
    }

    @MainActor
    static func hasConsumedTreeFocus(_ host: DocumentHost) -> Bool {
        showsTree(for: host) && host.isTreeFocused && host.isTreeFocusConsumed
    }
}

struct FolderTreeView: View {
    @ObservedObject var host: DocumentHost
    @FocusState private var treeHasFocus: Bool

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
            .focusable()
            .focused($treeHasFocus)
            .onAppear { applyTreeFocusIfNeeded() }
            .onChange(of: host.isTreeFocused) { _, _ in
                applyTreeFocusIfNeeded()
            }
        }
    }

    private func applyTreeFocusIfNeeded() {
        guard host.isTreeFocused, FolderChrome.showsTree(for: host) else { return }
        treeHasFocus = true
        FolderChrome.consumeTreeFocus(host)
    }
}

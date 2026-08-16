import Foundation

enum EditorCommands {
    @MainActor
    static func foldCurrent(on host: DocumentHost) {
        host.foldCurrent()
    }

    @MainActor
    static func presentOutline(on host: DocumentHost) {
        host.presentOutline()
    }

    @MainActor
    static func toggleSourcePreview(on host: DocumentHost) {
        host.toggleSourcePreview()
    }

    @MainActor
    static func focusTree(on host: DocumentHost) {
        host.focusTree()
    }
}

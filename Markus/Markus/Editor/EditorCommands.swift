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

    @MainActor
    static func presentFind(on host: DocumentHost) {
        host.presentFind()
    }

    @MainActor
    static func presentGoToLine(on host: DocumentHost) {
        host.presentGoToLine()
    }

    @MainActor
    static func foldAll(on host: DocumentHost) {
        host.foldAll()
    }

    @MainActor
    static func unfoldAll(on host: DocumentHost) {
        host.unfoldAll()
    }
}

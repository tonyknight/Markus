import SwiftUI
import UniformTypeIdentifiers

/// A single, dynamic `.fileImporter` presentation shared by the file-open
/// and folder-open flows. `ContentView` used to chain two independent
/// `.fileImporter` modifiers onto the same view — SwiftUI does not support
/// that, and silently picks one winner, leaving the other dead. Routing
/// both through one presentation, distinguished by which flag on
/// `DocumentHost` is set, fixes that without changing the host's published
/// state shape.
enum FileImporterChrome {
    /// Shipped kinds plus plain text (unknown extensions still open as markdown).
    /// `public.markdown` is the system UTI macOS tags `.md` with — include
    /// it explicitly so the Open panel is not limited to our imported
    /// Daring Fireball UTI. `UTType.markdown` is not available on the
    /// macOS 14 / iOS 17 SDK this app targets.
    static var documentContentTypes: [UTType] {
        var types = DocumentKind.shipped.map(\.contentType)
        if let publicMarkdown = UTType("public.markdown"),
           !types.contains(where: { $0.identifier == publicMarkdown.identifier }) {
            types.insert(publicMarkdown, at: 0)
        }
        return types + [.plainText]
    }

    @MainActor
    static func isPresented(for host: DocumentHost) -> Bool {
        host.isImporterPresented || host.isFolderImporterPresented
    }

    @MainActor
    static func setPresented(_ presented: Bool, on host: DocumentHost) {
        guard !presented else { return }
        host.isImporterPresented = false
        host.isFolderImporterPresented = false
    }

    @MainActor
    static func allowedContentTypes(for host: DocumentHost) -> [UTType] {
        host.isFolderImporterPresented ? FolderChrome.folderContentTypes : documentContentTypes
    }

    @MainActor
    static func handle(_ result: Result<[URL], Error>, isFolder: Bool, on host: DocumentHost) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                if isFolder {
                    host.openFolder(url)
                } else {
                    host.openStandaloneFile(url)
                }
            }
        case .failure:
            host.errorMessage = isFolder ? "Could not open folder." : "Could not open file."
        }
        host.isImporterPresented = false
        host.isFolderImporterPresented = false
    }
}

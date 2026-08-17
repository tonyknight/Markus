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
    static var markdownContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return types
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
        host.isFolderImporterPresented ? FolderChrome.folderContentTypes : markdownContentTypes
    }

    @MainActor
    static func handle(_ result: Result<[URL], Error>, on host: DocumentHost) {
        let isFolder = host.isFolderImporterPresented
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

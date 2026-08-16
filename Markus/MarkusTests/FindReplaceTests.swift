import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct FindReplaceTests {
    private var fixture: String {
        """
        ## Heading two

        Hidden SECRET body.

        After fold.
        """
    }

    @Test func findAndReplaceHitFoldedBodyAndSaveWritesFullUTF8() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.foldStore.isFolded(heading.id))
        #expect(view.collapsedFragmentCount > 0)

        let storage = try #require(view.textStorage)
        let match = try #require(FindReplace.search("SECRET", in: storage))
        #expect(NSMaxRange(match) <= storage.length)
        let matched = (storage.string as NSString).substring(with: match)
        #expect(matched == "SECRET")

        let replaced = FindReplace.replace(match, with: "FOUND", in: storage)
        #expect(replaced)
        view.syncBlocksFromStorage()
        view.ensureLayout()
        #expect(storage.string.contains("FOUND"))
        #expect(!storage.string.contains("SECRET"))

        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.string.contains("FOUND"))
        #expect(DocumentSave.writeUTF8(from: storage) == Data(view.string.utf8))
        #expect(String(data: DocumentSave.writeUTF8(from: storage), encoding: .utf8)?.contains("FOUND") == true)
    }
}

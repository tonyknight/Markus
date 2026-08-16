import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct EditorQoLTests {
    private var fixture: String {
        """
        ## Heading two

        A paragraph under the H2.

        ## Following two
        """
    }

    @Test func goToLineUsesSourceLineMapAndStatusReportsLine() throws {
        let host = DocumentHost()
        host.session.editor.loadMarkdown(fixture)
        host.session.editor.setMode(.source)
        host.session.editor.ensureLayout()

        host.goToLine(1)
        let line1Y = try #require(host.session.editor.y(forSourceLine: 1))
        #expect(host.session.editor.lastJumpedPackedY == line1Y)
        #expect(host.statusSourceLine == 1)
        #expect(host.statusText.contains("1"))
        #expect(host.statusText.contains("Source") || host.statusText.contains("Preview"))

        let later = try #require(host.session.editor.visibleSourceLines.last { $0 > 1 })
        host.goToLine(later)
        let laterY = try #require(host.session.editor.y(forSourceLine: later))
        #expect(host.session.editor.lastJumpedPackedY == laterY)
        #expect(laterY > line1Y)
        #expect(host.statusSourceLine == later)
        #expect(host.statusText.contains("\(later)"))
    }

    @Test func zoomScalesFontsWithoutRewritingMarkdownBytes() throws {
        let host = DocumentHost()
        host.session.editor.loadMarkdown(fixture)
        host.session.editor.setMode(.source)
        host.session.editor.ensureLayout()
        let storage = host.session.editor.documentTextStorage
        let beforeBytes = DocumentSave.writeUTF8(from: storage)
        let beforeSize = try #require(fontSize(at: 0, in: storage))

        host.setZoomScale(1.5)
        host.session.editor.ensureLayout()
        let afterSize = try #require(fontSize(at: 0, in: storage))
        #expect(afterSize > beforeSize)
        #expect(DocumentSave.writeUTF8(from: storage) == beforeBytes)
        #expect(host.session.editor.string == fixture)
    }

    @Test func shortcutCommandsInvokeTheSameHostMethodsAsMenus() throws {
        let host = DocumentHost()
        host.session.editor.loadMarkdown(fixture)
        host.session.editor.setMode(.preview)
        host.session.editor.ensureLayout()
        host.session.editor.jumpToSourceLine(1)

        #expect(!host.isOutlinePresented)
        EditorCommands.presentOutline(on: host)
        #expect(host.isOutlinePresented)
        host.presentOutline()
        #expect(host.isOutlinePresented)

        EditorCommands.toggleSourcePreview(on: host)
        #expect(host.mode == .source)
        host.toggleSourcePreview()
        #expect(host.mode == .preview)

        #expect(!host.isFolderImporterPresented)
        EditorCommands.focusTree(on: host)
        #expect(host.isFolderImporterPresented)
        #expect(!FolderChrome.showsTree(for: host))

        EditorCommands.foldCurrent(on: host)
        let heading = try #require(host.session.editor.blocks.first { $0.id.startLine == 1 })
        #expect(host.session.editor.foldStore.isFolded(heading.id))
    }

    @Test func findChromePresentsAndHitsFoldedBodyThenReplaceSavesFullUTF8() throws {
        let host = DocumentHost()
        let markdown = """
        ## Heading two

        Hidden SECRET body.

        After fold.
        """
        host.session.editor.loadMarkdown(markdown)
        host.session.editor.setMode(.source)
        host.session.editor.ensureLayout()

        #expect(!host.isFindPresented)
        EditorCommands.presentFind(on: host)
        #expect(host.isFindPresented)
        host.presentFind()
        #expect(host.isFindPresented)

        let heading = try #require(host.session.editor.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        host.session.editor.foldStore.toggle(heading.id)
        host.session.editor.applyFolds()
        host.session.editor.ensureLayout()
        #expect(host.session.editor.foldStore.isFolded(heading.id))

        let match = try #require(host.findFromChrome("SECRET"))
        let storage = host.session.editor.documentTextStorage
        #expect((storage.string as NSString).substring(with: match) == "SECRET")

        #expect(host.replaceFromChrome("FOUND"))
        #expect(storage.string.contains("FOUND"))
        #expect(!storage.string.contains("SECRET"))
        #expect(DocumentSave.writeUTF8(from: storage) == Data(host.session.editor.string.utf8))
        #expect(String(data: DocumentSave.writeUTF8(from: storage), encoding: .utf8)?.contains("FOUND") == true)
    }

    @Test func goToLineChromePresentsAndConfirmJumpsLikeGoToLine() throws {
        let host = DocumentHost()
        host.session.editor.loadMarkdown(fixture)
        host.session.editor.setMode(.source)
        host.session.editor.ensureLayout()

        #expect(!host.isGoToLinePresented)
        EditorCommands.presentGoToLine(on: host)
        #expect(host.isGoToLinePresented)
        host.presentGoToLine()
        #expect(host.isGoToLinePresented)

        let later = try #require(host.session.editor.visibleSourceLines.last { $0 > 1 })
        host.confirmGoToLine(later)
        let laterY = try #require(host.session.editor.y(forSourceLine: later))
        #expect(host.session.editor.lastJumpedPackedY == laterY)
        #expect(host.statusSourceLine == later)
        #expect(!host.isGoToLinePresented)
    }

    @Test func focusTreePresentsImporterOrConsumesFocusOnVisibleTree() throws {
        let host = DocumentHost(
            recents: RecentDocuments(defaults: UserDefaults(suiteName: "markus.qol.tree.\(UUID().uuidString)")!)
        )
        #expect(!host.isFolderImporterPresented)
        #expect(!FolderChrome.showsTree(for: host))
        host.focusTree()
        #expect(host.isFolderImporterPresented)
        #expect(!FolderChrome.showsTree(for: host))
        #expect(!FolderChrome.hasConsumedTreeFocus(host))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-qol-tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Notes\n".utf8).write(to: root.appendingPathComponent("notes.md"))

        host.isFolderImporterPresented = false
        host.openFolder(root)
        host.focusTree()
        #expect(FolderChrome.showsTree(for: host))
        #expect(host.isTreeFocused)
        FolderChrome.consumeTreeFocus(host)
        #expect(FolderChrome.hasConsumedTreeFocus(host))
    }

    @Test func jumpToSourceLineScrollsPackedYOnScreen() throws {
        let lines = (1...60).map { "Paragraph \($0) fills the viewport so later headings sit below.\n" }
        let markdown = "# Top\n\n" + lines.joined() + "\n## Later heading\n\nBody of later.\n"
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 80), foldStore: FoldStore())
        view.loadMarkdown(markdown)
        view.setMode(.source)
        view.ensureLayout()

        let later = try #require(OutlineJump.items(from: view.blocks, markdown: view.string).last?.sourceLine)
        let laterY = try #require(view.y(forSourceLine: later))
        #expect(laterY > view.bounds.height)

        view.jumpToSourceLine(later)
        #expect(view.lastJumpedPackedY == laterY)
        #expect(view.viewportContainsPackedY(laterY))
    }

    @Test func previewZoomScalesGFMSpanFontsWithoutRewritingMarkdown() throws {
        let markdown = """
        # Title

        ```
        let answer = 42
        ```

        Use `inline` here.
        """
        let host = DocumentHost()
        host.session.editor.loadMarkdown(markdown)
        #expect(host.session.editor.mode == .preview)
        host.session.editor.ensureLayout()
        let storage = host.session.editor.documentTextStorage
        let beforeBytes = DocumentSave.writeUTF8(from: storage)
        let headingRange = (markdown as NSString).range(of: "# Title")
        let codeRange = (markdown as NSString).range(of: "let answer = 42")
        let headingBefore = try #require(fontSize(at: headingRange.location, in: storage))
        let codeBefore = try #require(fontSize(at: codeRange.location, in: storage))

        host.setZoomScale(1.5)
        host.session.editor.ensureLayout()
        let headingAfter = try #require(fontSize(at: headingRange.location, in: storage))
        let codeAfter = try #require(fontSize(at: codeRange.location, in: storage))
        #expect(headingAfter > headingBefore)
        #expect(codeAfter > codeBefore)
        #expect(DocumentSave.writeUTF8(from: storage) == beforeBytes)
        #expect(host.session.editor.string == markdown)
    }

    private func fontSize(at index: Int, in storage: NSTextStorage) -> CGFloat? {
        guard storage.length > index,
              let font = storage.attribute(.font, at: index, effectiveRange: nil)
        else {
            return nil
        }
        #if os(macOS)
        return (font as? NSFont)?.pointSize
        #else
        return (font as? UIFont)?.pointSize
        #endif
    }
}

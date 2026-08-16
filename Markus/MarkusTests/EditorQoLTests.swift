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

        #expect(!host.isTreeFocused)
        EditorCommands.focusTree(on: host)
        #expect(host.isTreeFocused)
        host.focusTree()
        #expect(host.isTreeFocused)

        EditorCommands.foldCurrent(on: host)
        let heading = try #require(host.session.editor.blocks.first { $0.id.startLine == 1 })
        #expect(host.session.editor.foldStore.isFolded(heading.id))
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

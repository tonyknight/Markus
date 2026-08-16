import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct ModeChromeTests {
    @Test func newSessionAndHostDefaultToPreview() {
        let session = DocumentSession()
        #expect(session.mode == .preview)
        #expect(session.editor.mode == .preview)

        let host = DocumentHost()
        #expect(host.mode == .preview)
        #expect(host.session.mode == .preview)
        #expect(host.session.editor.mode == .preview)
    }

    @Test func setModeSwitchesSingleEditorWithoutChangingDirtyOrFolds() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-mode-\(UUID().uuidString).md")
        let markdown = """
        ## Heading two

        Hidden body.
        """
        try Data(markdown.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)
        let editorIdentity = ObjectIdentifier(session.editor)
        let heading = try #require(session.editor.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        session.editor.foldStore.toggle(heading.id)
        session.editor.applyFolds()
        #expect(!session.isDirty)
        let foldedIDs = session.editor.foldStore.foldedIDs

        session.setMode(.source)
        #expect(session.mode == .source)
        #expect(session.editor.mode == .source)
        #expect(ObjectIdentifier(session.editor) == editorIdentity)
        #expect(!session.isDirty)
        #expect(session.editor.foldStore.foldedIDs == foldedIDs)

        session.setMode(.preview)
        #expect(session.mode == .preview)
        #expect(session.editor.mode == .preview)
        #expect(ObjectIdentifier(session.editor) == editorIdentity)
        #expect(!session.isDirty)
        #expect(session.editor.foldStore.foldedIDs == foldedIDs)

        let host = DocumentHost(session: session, recents: RecentDocuments())
        host.setMode(.source)
        #expect(host.mode == .source)
        #expect(host.session.editor.mode == .source)
        #expect(ObjectIdentifier(host.session.editor) == editorIdentity)
        host.setMode(.preview)
        #expect(host.mode == .preview)
        #expect(ObjectIdentifier(host.session.editor) == editorIdentity)
    }

    #if os(macOS)
    @Test func macTitleBarPickerBindsToExclusiveHostMode() {
        let host = DocumentHost()
        #expect(ModeChrome.macItemPlacement == .principal)
        #expect(ModeChrome.showsMacTitleBarControl)
        #expect(!ModeChrome.showsIOSSegmentedControl)

        ModeChrome.select(.source, on: host)
        let editorIdentity = ObjectIdentifier(host.session.editor)
        #expect(host.mode == .source)
        #expect(host.session.editor.mode == .source)

        ModeChrome.select(.preview, on: host)
        #expect(host.mode == .preview)
        #expect(host.session.editor.mode == .preview)
        #expect(ObjectIdentifier(host.session.editor) == editorIdentity)
    }
    #endif

    @Test func iOSSegmentedControlBindsToExclusiveHostModeWithoutMacTitleBar() {
        #expect(ModeChrome.iosItemPlacement == .navigationBar)
        #if os(macOS)
        #expect(!ModeChrome.showsIOSSegmentedControl)
        #expect(ModeChrome.showsMacTitleBarControl)
        #else
        #expect(ModeChrome.showsIOSSegmentedControl)
        #expect(!ModeChrome.showsMacTitleBarControl)
        #endif

        let host = DocumentHost()
        let editorIdentity = ObjectIdentifier(host.session.editor)
        ModeChrome.select(.source, on: host)
        #expect(host.mode == .source)
        #expect(host.session.editor.mode == .source)
        ModeChrome.select(.preview, on: host)
        #expect(host.mode == .preview)
        #expect(ObjectIdentifier(host.session.editor) == editorIdentity)
    }
}

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

        let host = DocumentHost()
        let editorIdentity = ObjectIdentifier(host.session.editor)
        ModeChrome.select(.source, on: host)
        #expect(host.mode == .source)
        #expect(host.session.editor.mode == .source)
        ModeChrome.select(.preview, on: host)
        #expect(host.mode == .preview)
        #expect(ObjectIdentifier(host.session.editor) == editorIdentity)
    }

    #if os(macOS)
    /// Replaces this file's former `ModeChrome.showsMacTitleBarControl` /
    /// `.showsIOSSegmentedControl` compile-time-flag pairs (N9: reading a
    /// `#if os(macOS) true #else false #endif` flag back only proves the
    /// compiler's own branch, never live behaviour). Mirrors
    /// `MacTitleBarChromeTests.macTitleBarToolbarHasOnlyTheModePickerAndNothingElse`,
    /// this ticket's own precedent for the identical problem: materialize a
    /// real `MarkdownDocument`'s window/toolbar and inspect what actually
    /// got built. That test already proves exclusivity (`toolbar.items.count
    /// == 1` — nothing that would only exist for iOS's own toolbar items,
    /// which don't even compile into the mac target). What it does not
    /// prove — and what this test adds — is that the sole item is genuinely
    /// the Source/Preview mode picker rather than merely "a lone item":
    /// `DocumentModePicker` uses `.pickerStyle(.segmented)`, so the item's
    /// materialized view subtree must contain a real AppKit segmented
    /// control. This would fail if the picker were removed from the
    /// toolbar (no item, or the segmented-control descendant vanishes) or
    /// swapped for a non-segmented control.
    @Test func macTitleBarToolbarsSoleItemIsGenuinelyTheSegmentedModePicker() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let toolbar = try #require(window.toolbar)
        #expect(toolbar.items.count == 1)
        let item = try #require(toolbar.items.first)
        let view = try #require(item.view)
        #expect(viewTreeContainsSegmentedControl(view))
    }

    private func viewTreeContainsSegmentedControl(_ view: NSView) -> Bool {
        if String(describing: type(of: view)).contains("SegmentedControl") {
            return true
        }
        return view.subviews.contains { viewTreeContainsSegmentedControl($0) }
    }
    #endif
}

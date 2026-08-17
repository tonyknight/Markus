import Foundation
#if os(macOS)
import AppKit
#endif
import Testing
@testable import Markus

@MainActor
struct MacTabsTests {
    @Test func macUsesNSDocumentTabbingNotSwiftUITabBar() {
        #if os(macOS)
        #expect(MacDocumentChrome.usesNSDocumentTabbing)
        #expect(!MacDocumentChrome.usesSwiftUITabBar)
        #expect(MacDocumentChrome.windowTabbingMode == .preferred)
        #else
        #expect(!MacDocumentChrome.usesNSDocumentTabbing)
        #expect(!MacDocumentChrome.usesSwiftUITabBar)
        #endif
    }

    #if os(macOS)
    @Test func markdownDocumentPrefersTabsAndReusesFoldingSession() {
        let first = MarkdownDocument()
        let second = MarkdownDocument()

        #expect(type(of: first) == MarkdownDocument.self)
        #expect(ObjectIdentifier(first) != ObjectIdentifier(second))
        #expect(ObjectIdentifier(first.session) != ObjectIdentifier(second.session))
        #expect(first.session.editor !== second.session.editor)
        #expect(first.configuredTabbingMode == .preferred)
        #expect(second.configuredTabbingMode == .preferred)
        #expect(MarkdownDocument.tabbingIdentifier == MacDocumentChrome.tabbingIdentifier)
    }

    @Test func creatingMarkdownDocumentYieldsWindowController() {
        let document = MarkdownDocument()
        #expect(document.windowControllers.isEmpty)
        document.makeWindowControllers()
        #expect(document.windowControllers.count == 1)
        #expect(document.windowControllers.first?.window != nil)
    }

    /// Regression check for the AppKit-main-menu ticket: window geometry
    /// now gets set as the last step of `makeWindowControllers()` (T01),
    /// and `contentViewController` is now `MarkdownDocumentViewController`
    /// rather than a bare `NSHostingController` (T04). Neither change may
    /// disturb the real window's tabbing configuration, and two documents'
    /// windows must still carry the same tabbing identifier so AppKit can
    /// group them.
    @Test func windowsFromMakeWindowControllersKeepMatchingTabbingConfigurationAfterTheMenuChange() throws {
        let first = MarkdownDocument()
        first.makeWindowControllers()
        let second = MarkdownDocument()
        second.makeWindowControllers()

        let firstWindow = try #require(first.windowControllers.first?.window)
        let secondWindow = try #require(second.windowControllers.first?.window)

        #expect(firstWindow.tabbingMode == .preferred)
        #expect(secondWindow.tabbingMode == .preferred)
        #expect(firstWindow.tabbingIdentifier == MacDocumentChrome.tabbingIdentifier)
        #expect(firstWindow.tabbingIdentifier == secondWindow.tabbingIdentifier)
        #expect(NSWindow.allowsAutomaticWindowTabbing)
        #expect(firstWindow.contentViewController is MarkdownDocumentViewController)
    }

    @Test func documentControllerOpensUntitledMarkdownDocumentWithWindow() throws {
        let document = try MacDocumentLaunch.openUntitledDocument()
        let markdown = try #require(document as? MarkdownDocument)
        #expect(!markdown.windowControllers.isEmpty)
        #expect(markdown.host.showsEditor)
        #expect(markdown.session.fileURL == nil)
    }

    @Test func untitledAndReadFromDataShowEditorWithoutDiskURL() throws {
        let untitled = MarkdownDocument()
        #expect(untitled.session.fileURL == nil)
        #expect(untitled.host.showsEditor)

        let fromData = MarkdownDocument()
        try fromData.read(from: Data("# From data\n".utf8), ofType: "net.daringfireball.markdown")
        #expect(fromData.session.fileURL == nil)
        #expect(fromData.session.editor.string == "# From data\n")
        #expect(fromData.host.showsEditor)
    }

    @Test func openingSecondFileUsesNSDocumentNotSessionReplace() throws {
        #expect(MacDocumentChrome.standaloneFileOpenCreatesNewDocument)
        let firstURL = uniqueTempMarkdownURL()
        let secondURL = uniqueTempMarkdownURL()
        try Data("# First\n".utf8).write(to: firstURL)
        try Data("# Second\n".utf8).write(to: secondURL)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        let recents = RecentDocuments(defaults: UserDefaults(suiteName: "markus.tabs.\(UUID().uuidString)")!)
        let host = DocumentHost(recents: recents)
        host.openPicked(firstURL)
        #expect(host.session.fileURL == firstURL)

        host.openStandaloneFile(secondURL)
        #expect(host.session.fileURL == firstURL)
        #expect(host.session.editor.string == "# First\n")
        #expect(host.recents.items.map(\.url.standardizedFileURL).contains(secondURL.standardizedFileURL))
    }

    /// Proves the real production wiring (not a test substitute) shares
    /// one app-scoped `ThemeStore` across Mac documents/tabs (R9; J.27) —
    /// two real `MarkdownDocument()`s must resolve to the identical
    /// `ThemeStore.shared` instance through `host.themeStore`.
    @Test func twoMarkdownDocumentsShareTheSameAppScopedThemeStore() {
        let first = MarkdownDocument()
        let second = MarkdownDocument()
        #expect(ObjectIdentifier(first.host.themeStore) == ObjectIdentifier(second.host.themeStore))
        #expect(first.host.themeStore === ThemeStore.shared)
    }

    @Test func nsDocumentWriteClearsSessionDirty() throws {
        let document = MarkdownDocument()
        document.session.editor.insertTextAtCaret("# Saved\n")
        #expect(document.session.isDirty)

        let url = uniqueTempMarkdownURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url, ofType: "net.daringfireball.markdown")
        #expect(!document.session.isDirty)
        #expect(document.session.fileURL == url)
        #expect(document.hasUnautosavedChanges == false)
    }

    private func uniqueTempMarkdownURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-tabs-\(UUID().uuidString).md")
    }
    #else
    @Test func iOSChromeOpenReplacesSingleSession() throws {
        #expect(!MacDocumentChrome.standaloneFileOpenCreatesNewDocument)
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-ios-first-\(UUID().uuidString).md")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-ios-second-\(UUID().uuidString).md")
        try Data("# First\n".utf8).write(to: firstURL)
        try Data("# Second\n".utf8).write(to: secondURL)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        let host = DocumentHost()
        #expect(!host.showsEditor)
        host.openStandaloneFile(firstURL)
        #expect(host.showsEditor)
        host.openStandaloneFile(secondURL)
        #expect(host.session.fileURL == secondURL)
        #expect(host.session.editor.string == "# Second\n")
    }
    #endif
}

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
    #endif
}

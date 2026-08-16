import SwiftUI
#if os(macOS)
import AppKit
#endif

enum MacDocumentChrome {
    static var usesNSDocumentTabbing: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var standaloneFileOpenCreatesNewDocument: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var usesSwiftUITabBar: Bool { false }

    #if os(macOS)
    static let windowTabbingMode: NSWindow.TabbingMode = .preferred
    static let tabbingIdentifier = "Markus.MarkdownDocument"

    static func applyPreferredTabbing(to window: NSWindow) {
        NSWindow.allowsAutomaticWindowTabbing = true
        window.tabbingMode = windowTabbingMode
        window.tabbingIdentifier = tabbingIdentifier
    }
    #endif
}

import Foundation
#if os(macOS)
import AppKit
#endif
import Testing
@testable import Markus

#if os(macOS)
@MainActor
struct MacTitleBarChromeTests {
    /// The document title bar is a real, live SwiftUI `.toolbar { }` that
    /// AppKit materializes into a genuine `NSToolbar` on the window (one
    /// `NSToolbarItem` per SwiftUI toolbar view, plus one auto-inserted
    /// flexible space). Counting that live item set — rather than reading
    /// back a compile-time `#if os(macOS)` flag — is what actually proves
    /// the removed buttons are gone from the real window, per N9.
    @Test func macTitleBarToolbarHasOnlyTheModePickerAndNothingElse() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let toolbar = try #require(window.toolbar)
        // Only the Source/Preview mode picker, per the ticket's own
        // Acceptance Criteria ("title bar contains only the Source/Preview
        // control") — an unconditional "only", so Outline and Settings
        // are gone too, alongside Open, Open Folder, Save, Revert, Fold,
        // Toggle Mode, Find, Go to Line, Tree, and Recents. Neither
        // Outline nor Settings has a macOS entry point yet (that's a
        // later ticket's ribbon rail / settings surface), but the AC as
        // written carves out no exception, so they wait too.
        #expect(toolbar.items.count == 1)
    }
}
#endif

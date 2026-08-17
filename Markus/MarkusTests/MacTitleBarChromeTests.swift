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
    @Test func macTitleBarToolbarHasOnlyModePickerOutlineSettingsAndTheAutoSpacer() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let toolbar = try #require(window.toolbar)
        // Source/Preview mode picker, Outline jump menu, Settings button,
        // plus SwiftUI's one auto-inserted flexible-space item. Open, Open
        // Folder, Save, Revert, Fold, Toggle Mode, Find, Go to Line, Tree,
        // and Recents must not be present — they're superseded by the
        // AppKit File/Edit menus (or, for Recents, folded under the
        // "Open Recent" submenu; Toggle duplicates the mode picker itself).
        #expect(toolbar.items.count == 4)
    }
}
#endif

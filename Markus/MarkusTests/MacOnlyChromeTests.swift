import Foundation
import Testing
@testable import Markus

struct MacOnlyChromeTests {
    @Test func tabsAndMinimapAreMacOnlyAndIOSHasNeither() {
        #expect(!MacOnlyChrome.usesSwiftUITabBar)
        #if os(macOS)
        #expect(MacOnlyChrome.hasNSDocumentTabbingSurface)
        #expect(MacOnlyChrome.hasMinimapInChrome)
        #expect(MacOnlyChrome.minimapIsRequired)
        #else
        #expect(!MacOnlyChrome.hasNSDocumentTabbingSurface)
        #expect(!MacOnlyChrome.hasMinimapInChrome)
        #expect(!MacOnlyChrome.minimapIsRequired)
        #endif
    }
}

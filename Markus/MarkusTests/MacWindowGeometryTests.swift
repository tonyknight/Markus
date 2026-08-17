import Foundation
#if os(macOS)
import AppKit
#endif
import Testing
@testable import Markus

#if os(macOS)
@MainActor
struct MacWindowGeometryTests {
    @Test func threeQuarterFrameIsPinnedToTopLeftOfVisibleFrame() {
        let visibleFrame = NSRect(x: 40, y: 0, width: 1600, height: 1000)
        let frame = MacWindowGeometry.windowFrame(forVisibleFrame: visibleFrame)

        #expect(frame.width == visibleFrame.width * 0.75)
        #expect(frame.height == visibleFrame.height * 0.75)
        // Pinned to the top-left corner: left edge matches the screen's
        // left edge, top edge matches the screen's top edge (AppKit y is
        // bottom-up, so "top" is maxY).
        #expect(frame.minX == visibleFrame.minX)
        #expect(frame.maxY == visibleFrame.maxY)
        // Not the old fixed 960x720 rect.
        #expect(frame.width != 960 || frame.height != 720)
    }

    @Test func makeWindowControllersSizesAndPositionsTheRealWindow() throws {
        let screen = try #require(NSScreen.main)
        let expected = MacWindowGeometry.windowFrame(forVisibleFrame: screen.visibleFrame)

        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)

        #expect(window.frame.width == expected.width)
        #expect(window.frame.height == expected.height)
        #expect(window.frame.minX == expected.minX)
        #expect(window.frame.maxY == expected.maxY)
        // Regression guard: the window must not still be the old fixed
        // 960x720 rect at the origin.
        #expect(!(window.frame.width == 960 && window.frame.height == 720 && window.frame.origin == .zero))
    }
}
#endif

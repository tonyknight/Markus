import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct MacMinimapTests {
    private var fixture: String {
        """
        ## Heading two

        A paragraph under the H2.

        ```swift
        let answer = 42
        ```
        """
    }

    #if os(macOS)
    @Test func minimapUsesCurrentModeAndCompressesFoldedPackedY() throws {
        #expect(MacMinimapChrome.showsMinimap)

        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.preview)
        view.ensureLayout()

        let unfolded = MacMinimapChrome.snapshot(from: view)
        #expect(unfolded.mode == .preview)
        let paragraphLine = 3
        #expect(unfolded.visibleSourceLines.contains(paragraphLine))
        let unfoldedHeight = unfolded.packedHeight
        #expect(unfoldedHeight > 0)

        view.setMode(.source)
        view.ensureLayout()
        #expect(MacMinimapChrome.snapshot(from: view).mode == .source)
        view.setMode(.preview)
        view.ensureLayout()

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()

        let folded = MacMinimapChrome.snapshot(from: view)
        #expect(folded.packedHeight < unfoldedHeight)
        #expect(!folded.visibleSourceLines.contains(paragraphLine))
        let headingY = try #require(folded.map.y(forSourceLine: 1))
        #expect(folded.sourceLine(atMinimapY: headingY) == 1)

        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()

        let restored = MacMinimapChrome.snapshot(from: view)
        #expect(restored.visibleSourceLines.contains(paragraphLine))
        #expect(abs(restored.packedHeight - unfoldedHeight) < 1)
        #expect(restored.mode == .preview)
    }
    #endif
}

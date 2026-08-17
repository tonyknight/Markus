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

    // MARK: - Structural rendering (T01)

    @Test func snapshotClassifiesHeadingFenceAndBodyLinesInsteadOfUniformBars() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let snapshot = MacMinimapChrome.snapshot(from: view)
        #expect(snapshot.kind(forSourceLine: 1) == .heading)
        #expect(snapshot.kind(forSourceLine: 3) == .body)
        #expect(snapshot.kind(forSourceLine: 5) == .fence)
    }

    @Test func renderPlanCoversAllThreeStructuralKindsRatherThanOneUniformKind() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let snapshot = MacMinimapChrome.snapshot(from: view)
        let bars = MinimapRenderer.bars(from: snapshot)
        #expect(bars.count == snapshot.map.entries.count)
        let kinds = Set(bars.map(\.kind))
        #expect(kinds == [.heading, .fence, .body])
    }

    @Test func minimapDrawsMoreThanOneDistinctColourRatherThanUniformGreyBars() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let minimap = MacMinimapView(frame: CGRect(x: 0, y: 0, width: 120, height: 400))
        minimap.snapshot = MacMinimapChrome.snapshot(from: view)

        let rep = try #require(minimap.bitmapImageRepForCachingDisplay(in: minimap.bounds))
        minimap.cacheDisplay(in: minimap.bounds, to: rep)

        let colours = distinctOpaqueColours(in: rep)
        // Background fill plus at least two differently-coloured bar kinds.
        #expect(colours.count >= 3)
    }

    // MARK: - Viewport indicator overlay (T02)

    private var longFixture: String {
        (1...40).map { "Paragraph line \($0) with enough words to take up real vertical space." }.joined(separator: "\n\n")
    }

    @Test func viewportIndicatorIsShorterThanTheMinimapWhenContentExceedsTheViewport() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 200), foldStore: FoldStore())
        view.loadMarkdown(longFixture)
        view.setMode(.source)
        view.ensureLayout()
        #expect(view.layoutHeight > view.bounds.height)

        let snapshot = MacMinimapChrome.snapshot(from: view)
        let minimapBounds = CGRect(x: 0, y: 0, width: 120, height: 400)
        let indicator = MacMinimapChrome.viewportRect(in: minimapBounds, snapshot: snapshot)

        #expect(indicator.height < minimapBounds.height)
        #expect(indicator.origin.y == 0)
    }

    @Test func viewportIndicatorHeightGrowsWithTheEditorsVisibleHeight() throws {
        let shortView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 150), foldStore: FoldStore())
        shortView.loadMarkdown(longFixture)
        shortView.setMode(.source)
        shortView.ensureLayout()

        let tallView = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 450), foldStore: FoldStore())
        tallView.loadMarkdown(longFixture)
        tallView.setMode(.source)
        tallView.ensureLayout()

        let minimapBounds = CGRect(x: 0, y: 0, width: 120, height: 400)
        let shortIndicator = MacMinimapChrome.viewportRect(in: minimapBounds, snapshot: MacMinimapChrome.snapshot(from: shortView))
        let tallIndicator = MacMinimapChrome.viewportRect(in: minimapBounds, snapshot: MacMinimapChrome.snapshot(from: tallView))

        #expect(tallIndicator.height > shortIndicator.height)
    }

    private func distinctOpaqueColours(in rep: NSBitmapImageRep) -> Set<[Int]> {
        var colours: Set<[Int]> = []
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.01 else { continue }
                let bucket = [
                    Int(colour.redComponent * 20),
                    Int(colour.greenComponent * 20),
                    Int(colour.blueComponent * 20),
                ]
                colours.insert(bucket)
            }
        }
        return colours
    }
    #endif
}

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

    // MARK: - Click-to-scroll (T03)

    @Test func clickingTheMinimapInvokesCallbackWithTheSourceLineUnderThePoint() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let minimap = MacMinimapView(frame: CGRect(x: 0, y: 0, width: 120, height: 400))
        minimap.snapshot = MacMinimapChrome.snapshot(from: view)

        var clickedLine: Int?
        minimap.onClickSourceLine = { clickedLine = $0 }

        // The paragraph line (3) is where jumpToSourceLine should land —
        // find its view-space y by inverting sourceLine(atViewY:)'s scale.
        let paragraphLine = 3
        let snapshot = try #require(minimap.snapshot)
        let packedY = try #require(snapshot.map.y(forSourceLine: paragraphLine))
        let scale = minimap.bounds.height / snapshot.packedHeight
        let viewY = packedY * scale + 1

        let handled = minimap.handleClick(at: CGPoint(x: 10, y: viewY))
        #expect(handled)
        #expect(clickedLine == paragraphLine)
    }

    @Test func clickingBelowAllContentDoesNotInvokeTheCallback() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let minimap = MacMinimapView(frame: CGRect(x: 0, y: 0, width: 120, height: 400))
        minimap.snapshot = MacMinimapChrome.snapshot(from: view)

        var clickedLine: Int?
        minimap.onClickSourceLine = { clickedLine = $0 }

        let handled = minimap.handleClick(at: CGPoint(x: 10, y: minimap.bounds.height + 50))
        #expect(!handled)
        #expect(clickedLine == nil)
    }

    @Test func clickingWithNoSnapshotDoesNotInvokeTheCallback() throws {
        let minimap = MacMinimapView(frame: CGRect(x: 0, y: 0, width: 120, height: 400))
        var clickedLine: Int?
        minimap.onClickSourceLine = { clickedLine = $0 }

        let handled = minimap.handleClick(at: CGPoint(x: 10, y: 10))
        #expect(!handled)
        #expect(clickedLine == nil)
    }

    // MARK: - Downsampling and fold-awareness (T04)

    private func syntheticSnapshot(entryCount: Int, headingLines: Set<Int> = []) -> MinimapSnapshot {
        let lineHeight: CGFloat = 14
        let entries = (1...entryCount).map { line in
            SourceLineMap.Entry(sourceLine: line, y: CGFloat(line - 1) * lineHeight, height: lineHeight)
        }
        return MinimapSnapshot(
            mode: .source,
            packedHeight: CGFloat(entryCount) * lineHeight,
            visibleSourceLines: Array(1...entryCount),
            map: SourceLineMap(entries: entries),
            headingLines: headingLines,
            fenceLines: [],
            visiblePackedRect: .zero
        )
    }

    @Test func downsamplingCapsBarsRegardlessOfDocumentSize() {
        let snapshot = syntheticSnapshot(entryCount: 5000)

        let bars = MinimapRenderer.bars(from: snapshot)
        #expect(bars.count <= MinimapRenderer.defaultMaxBars)
        #expect(bars.count < snapshot.map.entries.count)
    }

    @Test func smallDocumentsKeepOneBarPerLineBelowTheDownsamplingThreshold() {
        let snapshot = syntheticSnapshot(entryCount: 10)

        let bars = MinimapRenderer.bars(from: snapshot)
        #expect(bars.count == snapshot.map.entries.count)
    }

    @Test func foldedContentDoesNotRenderInTheBarsAsIfStillExpanded() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let unfolded = MacMinimapChrome.snapshot(from: view)
        let unfoldedBars = MinimapRenderer.bars(from: unfolded)
        let unfoldedSpan = unfoldedBars.map { $0.y + $0.height }.max() ?? 0

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()

        let folded = MacMinimapChrome.snapshot(from: view)
        let foldedBars = MinimapRenderer.bars(from: folded)
        let foldedSpan = foldedBars.map { $0.y + $0.height }.max() ?? 0

        #expect(foldedSpan <= folded.packedHeight + 0.5)
        #expect(foldedSpan < unfoldedSpan)
    }

    @Test func barsAreCachedOnSnapshotAssignmentNotRecomputedPerDraw() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let minimap = MacMinimapView(frame: CGRect(x: 0, y: 0, width: 120, height: 400))
        let snapshot = MacMinimapChrome.snapshot(from: view)
        minimap.snapshot = snapshot

        let expected = MinimapRenderer.bars(from: snapshot)
        #expect(minimap.bars == expected)

        // Multiple repaints (via the real display machinery, as in the
        // rasterization test above) must not need to recompute — the
        // cached array set at snapshot-assignment time stays exactly as
        // it was.
        let rep = try #require(minimap.bitmapImageRepForCachingDisplay(in: minimap.bounds))
        minimap.cacheDisplay(in: minimap.bounds, to: rep)
        minimap.cacheDisplay(in: minimap.bounds, to: rep)
        #expect(minimap.bars == expected)
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

import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#endif

/// Which structural role a minimap bar represents, so the minimap can
/// reflect document structure (heading / fenced code / body) instead of
/// drawing uniform grey bars for every line (R18).
enum MinimapBarKind: Equatable {
    case heading
    case fence
    case body
}

/// One bar in the minimap's render plan: a vertical span of the packed
/// layout, its structural kind, and how much of the track width to fill
/// (a lightweight density signal derived from rendered line height).
struct MinimapBar: Equatable {
    var y: CGFloat
    var height: CGFloat
    var kind: MinimapBarKind
    var coverage: CGFloat
}

struct MinimapSnapshot: Equatable {
    var mode: EditorMode
    var packedHeight: CGFloat
    var visibleSourceLines: [Int]
    var map: SourceLineMap
    var headingLines: Set<Int>
    var fenceLines: Set<Int>
    var visiblePackedRect: CGRect

    func sourceLine(atMinimapY y: CGFloat) -> Int? {
        map.sourceLine(atY: y)
    }

    func kind(forSourceLine line: Int) -> MinimapBarKind {
        if headingLines.contains(line) { return .heading }
        if fenceLines.contains(line) { return .fence }
        return .body
    }
}

/// Turns a `MinimapSnapshot` into a bounded list of `MinimapBar`s to draw.
/// Kept as a pure function, separate from `MacMinimapView`, so the render
/// plan is directly testable without rasterizing anything.
///
/// `snapshot.map.entries` already excludes hidden/folded lines and packs
/// what remains contiguously (`FoldingTextView.packedSourceLineEntries()`),
/// so fold-awareness falls out of building bars from those entries — a
/// folded region simply isn't present to draw a bar for.
enum MinimapRenderer {
    /// Above this many visible lines, bars are bucketed into a fixed count
    /// rather than drawn one per line, so a 5 MB document doesn't drive
    /// per-redraw work proportional to its line count (G.19).
    static let defaultMaxBars = 512

    static func bars(from snapshot: MinimapSnapshot, maxBars: Int = defaultMaxBars) -> [MinimapBar] {
        let entries = snapshot.map.entries
        guard !entries.isEmpty else { return [] }
        let maxHeight = entries.map(\.height).max() ?? 1

        func coverage(for entry: SourceLineMap.Entry) -> CGFloat {
            maxHeight > 0 ? min(1, entry.height / maxHeight) : 1
        }

        guard entries.count > maxBars, snapshot.packedHeight > 0 else {
            return entries.map { entry in
                MinimapBar(
                    y: entry.y,
                    height: entry.height,
                    kind: snapshot.kind(forSourceLine: entry.sourceLine),
                    coverage: coverage(for: entry)
                )
            }
        }

        // Downsample: bucket entries into `maxBars` fixed-height slices of
        // the packed layout, one bar per slice, in a single forward pass —
        // bounded output regardless of how many lines are visible.
        let bucketHeight = snapshot.packedHeight / CGFloat(maxBars)
        var bars: [MinimapBar] = []
        bars.reserveCapacity(maxBars)
        var bucketIndex = -1
        var bucketKind = MinimapBarKind.body
        var bucketCoverage: CGFloat = 0
        var bucketHasEntries = false

        func flush() {
            guard bucketHasEntries, bucketIndex >= 0 else { return }
            bars.append(
                MinimapBar(
                    y: CGFloat(bucketIndex) * bucketHeight,
                    height: bucketHeight,
                    kind: bucketKind,
                    coverage: bucketCoverage
                )
            )
        }

        for entry in entries {
            let entryBucket = min(maxBars - 1, Int(entry.y / bucketHeight))
            if entryBucket != bucketIndex {
                flush()
                bucketIndex = entryBucket
                bucketKind = .body
                bucketCoverage = 0
                bucketHasEntries = false
            }
            bucketHasEntries = true
            let entryKind = snapshot.kind(forSourceLine: entry.sourceLine)
            if entryKind == .heading || (entryKind == .fence && bucketKind == .body) {
                bucketKind = entryKind
            }
            bucketCoverage = max(bucketCoverage, coverage(for: entry))
        }
        flush()
        return bars
    }
}

enum MacMinimapChrome {
    static var showsMinimap: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    @MainActor
    static func snapshot(from editor: FoldingTextView) -> MinimapSnapshot {
        var headingLines: Set<Int> = []
        var fenceLines: Set<Int> = []
        for block in editor.blocks {
            switch block.kind {
            case .heading:
                headingLines.formUnion(block.lines)
            case .fencedCode:
                fenceLines.formUnion(block.lines)
            case .other:
                break
            }
        }
        return MinimapSnapshot(
            mode: editor.mode,
            packedHeight: editor.layoutHeight,
            visibleSourceLines: editor.visibleSourceLines,
            map: editor.session.sourceLineMap(),
            headingLines: headingLines,
            fenceLines: fenceLines,
            visiblePackedRect: editor.currentVisiblePackedRect()
        )
    }

    /// Scales `snapshot.visiblePackedRect` (in packed layout coordinates)
    /// into `minimapBounds` using the same scale factor the bars are drawn
    /// with, so the viewport indicator lines up with the bars beneath it.
    static func viewportRect(in minimapBounds: CGRect, snapshot: MinimapSnapshot) -> CGRect {
        guard snapshot.packedHeight > 0, minimapBounds.height > 0 else { return .zero }
        let scale = minimapBounds.height / snapshot.packedHeight
        let y = minimapBounds.minY + snapshot.visiblePackedRect.minY * scale
        let height = max(2, snapshot.visiblePackedRect.height * scale)
        return CGRect(x: minimapBounds.minX, y: y, width: minimapBounds.width, height: height)
    }
}

#if os(macOS)
final class MacMinimapView: NSView {
    var snapshot: MinimapSnapshot? {
        didSet {
            // Bucketing is O(visible lines) — do it once here, when the
            // document actually changes, not inside draw() (called on
            // every repaint/scroll), so a 5 MB document doesn't redo
            // per-line work on every frame (G.19).
            bars = snapshot.map { MinimapRenderer.bars(from: $0) } ?? []
            needsDisplay = true
        }
    }

    private(set) var bars: [MinimapBar] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let snapshot, snapshot.packedHeight > 0 else { return }
        let scale = bounds.height / max(snapshot.packedHeight, 1)
        let trackWidth = max(2, bounds.width - 8)
        for bar in bars {
            color(for: bar.kind).setFill()
            let height = max(1, bar.height * scale)
            let width = max(2, trackWidth * bar.coverage)
            let rect = NSRect(x: 4, y: bar.y * scale, width: width, height: height)
            rect.fill()
        }

        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        MacMinimapChrome.viewportRect(in: bounds, snapshot: snapshot).fill()
    }

    private func color(for kind: MinimapBarKind) -> NSColor {
        switch kind {
        case .heading:
            return NSColor.controlAccentColor.withAlphaComponent(0.75)
        case .fence:
            return NSColor.systemOrange.withAlphaComponent(0.55)
        case .body:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.35)
        }
    }

    func sourceLine(atViewY y: CGFloat) -> Int? {
        guard let snapshot, snapshot.packedHeight > 0, bounds.height > 0 else { return nil }
        let packedY = y * (snapshot.packedHeight / bounds.height)
        return snapshot.sourceLine(atMinimapY: packedY)
    }

    /// Invoked with the source line under a click, so the host can scroll
    /// there via the existing `jumpToSourceLine` (R18) — set by
    /// `MacMinimapRepresentable`, not called directly by this view.
    var onClickSourceLine: ((Int) -> Void)?

    /// Resolves `point` to a source line via `sourceLine(atViewY:)` and
    /// invokes `onClickSourceLine`, mirroring
    /// `FoldingTextView.handleGutterClick(at:)`'s shape. Returns whether a
    /// line was found under the point.
    @discardableResult
    func handleClick(at point: CGPoint) -> Bool {
        guard let line = sourceLine(atViewY: point.y) else { return false }
        onClickSourceLine?(line)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleClick(at: point) { return }
        super.mouseDown(with: event)
    }
}

struct MacMinimapRepresentable: NSViewRepresentable {
    var editor: FoldingTextView

    func makeNSView(context: Context) -> MacMinimapView {
        let view = MacMinimapView()
        view.snapshot = MacMinimapChrome.snapshot(from: editor)
        view.onClickSourceLine = { [editor] line in
            editor.jumpToSourceLine(line)
        }
        return view
    }

    func updateNSView(_ nsView: MacMinimapView, context: Context) {
        editor.ensureLayout()
        nsView.snapshot = MacMinimapChrome.snapshot(from: editor)
    }
}
#endif

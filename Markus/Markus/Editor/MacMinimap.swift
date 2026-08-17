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
enum MinimapRenderer {
    static func bars(from snapshot: MinimapSnapshot) -> [MinimapBar] {
        let entries = snapshot.map.entries
        guard !entries.isEmpty else { return [] }
        let maxHeight = entries.map(\.height).max() ?? 1
        return entries.map { entry in
            MinimapBar(
                y: entry.y,
                height: entry.height,
                kind: snapshot.kind(forSourceLine: entry.sourceLine),
                coverage: maxHeight > 0 ? min(1, entry.height / maxHeight) : 1
            )
        }
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
            fenceLines: fenceLines
        )
    }
}

#if os(macOS)
final class MacMinimapView: NSView {
    var snapshot: MinimapSnapshot? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let snapshot, snapshot.packedHeight > 0 else { return }
        let scale = bounds.height / max(snapshot.packedHeight, 1)
        let trackWidth = max(2, bounds.width - 8)
        for bar in MinimapRenderer.bars(from: snapshot) {
            color(for: bar.kind).setFill()
            let height = max(1, bar.height * scale)
            let width = max(2, trackWidth * bar.coverage)
            let rect = NSRect(x: 4, y: bar.y * scale, width: width, height: height)
            rect.fill()
        }
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
}

struct MacMinimapRepresentable: NSViewRepresentable {
    var editor: FoldingTextView

    func makeNSView(context: Context) -> MacMinimapView {
        let view = MacMinimapView()
        view.snapshot = MacMinimapChrome.snapshot(from: editor)
        return view
    }

    func updateNSView(_ nsView: MacMinimapView, context: Context) {
        editor.ensureLayout()
        nsView.snapshot = MacMinimapChrome.snapshot(from: editor)
    }
}
#endif

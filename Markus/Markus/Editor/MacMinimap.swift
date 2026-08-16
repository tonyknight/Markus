import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#endif

struct MinimapSnapshot: Equatable {
    var mode: EditorMode
    var packedHeight: CGFloat
    var visibleSourceLines: [Int]
    var map: SourceLineMap

    func sourceLine(atMinimapY y: CGFloat) -> Int? {
        map.sourceLine(atY: y)
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
        MinimapSnapshot(
            mode: editor.mode,
            packedHeight: editor.layoutHeight,
            visibleSourceLines: editor.visibleSourceLines,
            map: editor.session.sourceLineMap()
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
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
        for entry in snapshot.map.entries {
            let height = max(1, entry.height * scale)
            let rect = NSRect(x: 4, y: entry.y * scale, width: max(2, bounds.width - 8), height: height)
            rect.fill()
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

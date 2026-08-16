import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SourceLineMap: Equatable {
    struct Entry: Equatable {
        var sourceLine: Int
        var y: CGFloat
        var height: CGFloat
    }

    var entries: [Entry]

    var visibleSourceLines: [Int] {
        entries.map(\.sourceLine)
    }

    func y(forSourceLine line: Int) -> CGFloat? {
        entries.first { $0.sourceLine == line }?.y
    }

    func height(forSourceLine line: Int) -> CGFloat? {
        entries.first { $0.sourceLine == line }?.height
    }

    func sourceLine(atY y: CGFloat) -> Int? {
        for entry in entries {
            let maxY = entry.y + entry.height
            if y >= entry.y && (y < maxY || (entry.height == 0 && y == entry.y)) {
                return entry.sourceLine
            }
        }
        if let last = entries.last, y >= last.y, y <= last.y + last.height {
            return last.sourceLine
        }
        return nil
    }
}

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A custom-drawn `NSTextAttachment` for a GFM table. It measures each
/// column's width from the widest cell in that column, draws a true aligned
/// grid (borders, per-cell text), and carries the table's full source byte
/// range so a selection over it can resolve back to the Markdown that
/// produced it (R11, feeds R22 in ticket 13).
///
/// This composes with `FoldingTextLayoutFragment` folding: it is a normal
/// character run in the text storage, laid out by the layout manager like
/// any other attachment. It never touches the buffer (N4) and never
/// participates in fold collapsing itself (N3) — folding a surrounding
/// block still owns that behavior at the fragment level.
final class TableAttachment: NSTextAttachment {
    let table: ParsedTable
    let font: PlatformFontType
    let cellPadding: CGFloat = 6
    let borderWidth: CGFloat = 1

    private(set) var columnWidths: [CGFloat] = []
    private(set) var rowHeights: [CGFloat] = []

    /// The table's full source byte range (`TableLayout.sourceRange`),
    /// unchanged from the parsed table it was built from.
    var sourceRange: Range<Int> { table.sourceRange }

    init(table: ParsedTable, font: PlatformFontType = PlatformFont.body(size: 14)) {
        self.table = table
        self.font = font
        super.init(data: nil, ofType: nil)
        measure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func measure() {
        let columnCount = table.alignments.count
        guard columnCount > 0 else {
            columnWidths = []
            rowHeights = []
            return
        }

        var widths = Array(repeating: CGFloat(0), count: columnCount)
        for row in table.rows {
            for (index, cell) in row.enumerated() where index < columnCount {
                let size = (cell as NSString).size(withAttributes: [.font: font])
                widths[index] = max(widths[index], ceil(size.width))
            }
        }
        columnWidths = widths.map { $0 + cellPadding * 2 }

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        rowHeights = Array(repeating: lineHeight + cellPadding * 2, count: table.rows.count)
    }

    /// Total size of the drawn grid: measured columns/rows plus the border
    /// strokes between and around them.
    var gridSize: CGSize {
        guard !columnWidths.isEmpty, !rowHeights.isEmpty else { return .zero }
        let width = columnWidths.reduce(0, +) + borderWidth * CGFloat(columnWidths.count + 1)
        let height = rowHeights.reduce(0, +) + borderWidth * CGFloat(rowHeights.count + 1)
        return CGSize(width: width, height: height)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let size = gridSize
        return CGRect(origin: .zero, size: size)
    }
}

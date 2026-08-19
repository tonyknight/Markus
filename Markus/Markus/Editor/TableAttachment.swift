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

    // MARK: - Grid geometry

    /// The rect for a given cell in local grid coordinates (origin top-left,
    /// y increasing downward), honoring the border stroke drawn between and
    /// around cells.
    func cellFrame(row: Int, column: Int) -> CGRect {
        guard row >= 0, row < rowHeights.count, column >= 0, column < columnWidths.count else {
            return .zero
        }
        let x = borderWidth + columnWidths[0..<column].reduce(0, +) + borderWidth * CGFloat(column)
        let y = borderWidth + rowHeights[0..<row].reduce(0, +) + borderWidth * CGFloat(row)
        return CGRect(x: x, y: y, width: columnWidths[column], height: rowHeights[row])
    }

    /// The horizontal origin at which to draw `textWidth`-wide text inside
    /// `cellRect`, honoring `column`'s alignment (left/center/right/none).
    /// `.none` (no alignment marker in the source) draws left-aligned, GFM's
    /// default rendering.
    func textOriginX(inCellRect cellRect: CGRect, column: Int, textWidth: CGFloat) -> CGFloat {
        let inset = cellRect.insetBy(dx: cellPadding, dy: 0)
        guard column >= 0, column < table.alignments.count else { return inset.minX }
        switch table.alignments[column] {
        case .left, .none:
            return inset.minX
        case .center:
            return inset.minX + max(0, (inset.width - textWidth) / 2)
        case .right:
            return inset.maxX - textWidth
        }
    }

    // MARK: - Drawing

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex: Int) -> PlatformImage? {
        let size = gridSize
        guard size.width > 0, size.height > 0 else { return nil }

        let width = Int(ceil(size.width))
        let height = Int(ceil(size.height))
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        draw(in: context, size: size)

        guard let cgImage = context.makeImage() else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    private func draw(in context: CGContext, size: CGSize) {
        // `CGContext` created above is bottom-up (Quartz native); our grid
        // math is top-down, so flip once up front and draw everything in
        // top-down coordinates from here on.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        drawBorders(in: context, size: size)
        drawCellText(in: context)
    }

    private func drawBorders(in context: CGContext, size: CGSize) {
        context.saveGState()
        context.setStrokeColor(PlatformColor.secondaryLabel.cgColor)
        context.setLineWidth(borderWidth)

        var x: CGFloat = borderWidth / 2
        for column in 0..<columnWidths.count {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: size.height))
            x += columnWidths[column] + borderWidth
        }
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: size.height))

        var y: CGFloat = borderWidth / 2
        for row in 0..<rowHeights.count {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            y += rowHeights[row] + borderWidth
        }
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: size.width, y: y))

        context.strokePath()
        context.restoreGState()
    }

    private func drawCellText(in context: CGContext) {
        #if os(macOS)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.current = previous }
        #else
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #endif

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.label,
        ]

        for (rowIndex, row) in table.rows.enumerated() {
            for (columnIndex, text) in row.enumerated() where columnIndex < columnWidths.count {
                let cellRect = cellFrame(row: rowIndex, column: columnIndex)
                guard !cellRect.isEmpty, !text.isEmpty else { continue }
                let textSize = (text as NSString).size(withAttributes: attributes)
                let x = textOriginX(inCellRect: cellRect, column: columnIndex, textWidth: textSize.width)
                let y = cellRect.minY + max(0, (cellRect.height - textSize.height) / 2)
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            }
        }
    }
}

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension NSAttributedString {
    /// Resolves every `TableAttachment` a Preview selection overlaps
    /// back to its full source byte range. A table attachment is one
    /// opaque glyph — there is no partial selection within it — so any
    /// overlap with `selection` resolves to the whole table (feeds R22
    /// in ticket 13). Returns every intersecting table's range, in
    /// document order, not just the first — the original single-result
    /// `tableSourceRange(intersecting:)` silently dropped every table
    /// past the first when a selection spanned more than one (flagged
    /// by ticket 01's review as a known gap; ticket 13 T06 is the fix).
    /// Returns an empty array when the selection touches no table.
    func tableSourceRanges(intersecting selection: NSRange) -> [Range<Int>] {
        var found: [Range<Int>] = []
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard let table = value as? TableAttachment else { return }
            let intersects = NSIntersectionRange(range, selection).length > 0
                || (selection.length == 0 && NSLocationInRange(selection.location, range))
            guard intersects else { return }
            found.append(table.sourceRange)
        }
        return found
    }
}

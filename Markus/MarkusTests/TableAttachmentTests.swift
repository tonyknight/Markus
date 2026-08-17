import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct TableAttachmentTests {
    private var parsedTable: ParsedTable {
        ParsedTable(
            sourceRange: 0..<42,
            alignments: [.left, .center, .right],
            rows: [
                ["Left", "Center", "Right"],
                ["a", "b", "c"],
                ["dd", "eeeeeeee", "ff"],
            ],
            headerRowIndex: 0
        )
    }

    private func location(in contentStorage: NSTextContentStorage) -> NSTextLocation {
        contentStorage.documentRange.location
    }

    @Test func measuresOneColumnWidthPerAlignmentAndOneRowHeightPerRow() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))

        #expect(attachment.columnWidths.count == 3)
        #expect(attachment.rowHeights.count == 3)
        #expect(attachment.columnWidths.allSatisfy { $0 > 0 })
        #expect(attachment.rowHeights.allSatisfy { $0 > 0 })
    }

    @Test func widerCellContentProducesAWiderColumn() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))

        // Column 1 ("Center" / "b" / "eeeeeeee") has the longest cell text
        // ("eeeeeeee", 8 chars) of any column, so with a monospaced font its
        // measured width must exceed both neighbors.
        #expect(attachment.columnWidths[1] > attachment.columnWidths[0])
        #expect(attachment.columnWidths[1] > attachment.columnWidths[2])
    }

    @Test func gridSizeIsSumOfColumnsAndRowsPlusBorders() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))

        let expectedWidth = attachment.columnWidths.reduce(0, +)
            + attachment.borderWidth * CGFloat(attachment.columnWidths.count + 1)
        let expectedHeight = attachment.rowHeights.reduce(0, +)
            + attachment.borderWidth * CGFloat(attachment.rowHeights.count + 1)

        #expect(attachment.gridSize.width == expectedWidth)
        #expect(attachment.gridSize.height == expectedHeight)
    }

    @Test func attachmentBoundsReportsTheMeasuredGridSize() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))
        let contentStorage = NSTextContentStorage()
        contentStorage.textStorage = NSTextStorage(string: "x")

        let bounds = attachment.attachmentBounds(
            for: [:],
            location: location(in: contentStorage),
            textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 400, height: 20),
            position: .zero
        )

        #expect(bounds.width == attachment.gridSize.width)
        #expect(bounds.height == attachment.gridSize.height)
    }

    // MARK: - Drawing geometry (T03)

    @Test func cellFramesTileLeftToRightAndTopToBottomSeparatedByOneBorderWidth() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))

        let c00 = attachment.cellFrame(row: 0, column: 0)
        let c01 = attachment.cellFrame(row: 0, column: 1)
        let c10 = attachment.cellFrame(row: 1, column: 0)

        #expect(c00.minX == attachment.borderWidth)
        #expect(c00.minY == attachment.borderWidth)
        #expect(c00.width == attachment.columnWidths[0])
        #expect(c00.height == attachment.rowHeights[0])

        // Column 1 starts one border width after column 0 ends.
        #expect(c01.minX == c00.maxX + attachment.borderWidth)
        // Row 1 starts one border width after row 0 ends.
        #expect(c10.minY == c00.maxY + attachment.borderWidth)
    }

    @Test func cellFrameOutOfBoundsReturnsZero() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))
        #expect(attachment.cellFrame(row: 99, column: 0) == .zero)
        #expect(attachment.cellFrame(row: 0, column: 99) == .zero)
    }

    @Test func textOriginHonorsPerColumnAlignment() {
        let attachment = TableAttachment(table: parsedTable, font: PlatformFont.monospaced(size: 14))
        let cellRect = CGRect(x: 100, y: 0, width: 60, height: 20)
        let textWidth: CGFloat = 20

        // Column 0 is .left: text sits at the cell's leading padded edge.
        let leftX = attachment.textOriginX(inCellRect: cellRect, column: 0, textWidth: textWidth)
        #expect(leftX == cellRect.minX + attachment.cellPadding)

        // Column 1 is .center: text is centered in the padded interior.
        let centerX = attachment.textOriginX(inCellRect: cellRect, column: 1, textWidth: textWidth)
        let inset = cellRect.insetBy(dx: attachment.cellPadding, dy: 0)
        #expect(centerX == inset.minX + (inset.width - textWidth) / 2)

        // Column 2 is .right: text sits at the cell's trailing padded edge.
        let rightX = attachment.textOriginX(inCellRect: cellRect, column: 2, textWidth: textWidth)
        #expect(rightX == cellRect.maxX - attachment.cellPadding - textWidth)

        // Left, center, and right must actually differ from one another.
        #expect(leftX != centerX)
        #expect(centerX != rightX)
        #expect(leftX != rightX)
    }

    // MARK: - Drawing (T03)

    @Test func imageForBoundsRendersAGridNeitherBlankNorSolid() throws {
        let table = ParsedTable(
            sourceRange: 0..<10,
            alignments: [.left, .right],
            rows: [["Head", "H2"], ["x", "y"]],
            headerRowIndex: 0
        )
        let attachment = TableAttachment(table: table, font: PlatformFont.monospaced(size: 14))
        let bounds = CGRect(origin: .zero, size: attachment.gridSize)

        let image = try #require(attachment.image(forBounds: bounds, textContainer: nil, characterIndex: 0))
        let rendered = try #require(rasterize(image))

        #expect(CGFloat(rendered.width) == bounds.width)
        #expect(CGFloat(rendered.height) == bounds.height)

        let fraction = try #require(opaquePixelFraction(of: rendered))
        // Border strokes and cell text must paint something...
        #expect(fraction > 0.02)
        // ...but drawing must not be a solid filled block either.
        #expect(fraction < 0.95)
    }

    private func rasterize(_ image: PlatformImage) -> CGImage? {
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    private func opaquePixelFraction(of rendered: CGImage) -> Double? {
        guard let data = rendered.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return nil }
        let bytesPerRow = rendered.bytesPerRow
        let bytesPerPixel = max(1, rendered.bitsPerPixel / 8)
        guard bytesPerPixel >= 4 else { return nil }
        var opaqueCount = 0
        var total = 0
        for y in 0..<rendered.height {
            for x in 0..<rendered.width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let alphaOffset = offset + 3
                guard alphaOffset < CFDataGetLength(data) else { continue }
                total += 1
                if bytes[alphaOffset] > 0 {
                    opaqueCount += 1
                }
            }
        }
        guard total > 0 else { return nil }
        return Double(opaqueCount) / Double(total)
    }
}

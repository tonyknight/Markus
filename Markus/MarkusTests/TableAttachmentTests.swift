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
}

import Foundation
import Testing
@testable import Markus

struct TableParsingTests {
    private var fixture: String {
        """
        # Title

        Intro paragraph.

        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        | dd | ee | ff |

        After table.
        """
    }

    @Test func parsesRowsColumnsAlignmentAndHeaderFlag() throws {
        let tables = TableParsing.parseTables(in: fixture)
        let table = try #require(tables.first)

        #expect(tables.count == 1)
        #expect(table.alignments == [.left, .center, .right])
        #expect(table.rows.count == 3)
        #expect(table.headerRowIndex == 0)
        #expect(table.rows[0] == ["Left", "Center", "Right"])
        #expect(table.rows[1] == ["a", "b", "c"])
        #expect(table.rows[2] == ["dd", "ee", "ff"])
    }

    @Test func sourceRangeCoversExactlyTheTableBytesIncludingDelimiterRow() {
        let tables = TableParsing.parseTables(in: fixture)
        guard let table = tables.first else {
            Issue.record("expected a parsed table")
            return
        }

        let data = Data(fixture.utf8)
        let slice = String(data: data.subdata(in: table.sourceRange), encoding: .utf8) ?? ""

        #expect(slice.hasPrefix("| Left"))
        #expect(slice.contains(":---"))
        #expect(slice.contains("| dd | ee | ff |"))
        #expect(!slice.contains("Intro paragraph"))
        #expect(!slice.contains("After table"))
    }

    @Test func noAlignmentMarkerProducesNoneAlignment() throws {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        let tables = TableParsing.parseTables(in: markdown)
        let table = try #require(tables.first)
        #expect(table.alignments == [.none, .none])
    }

    @Test func documentWithoutATableParsesToEmptyArray() {
        let tables = TableParsing.parseTables(in: "Just a paragraph, no table.")
        #expect(tables.isEmpty)
    }
}

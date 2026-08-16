import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct OutlineJumpTests {
    private var fixture: String {
        """
        # First

        Hidden under first.

        ## Second

        Body of second.
        """
    }

    @Test func outlineListsBlockIndexHeadingsAndJumpSetsCaretEvenWhenFolded() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(fixture)
        view.setMode(.source)
        view.ensureLayout()

        let index = BlockIndex.build(markdown: fixture)
        let headings = index.filter {
            if case .heading = $0.kind { return true }
            return false
        }
        #expect(headings.count == 2)

        let items = OutlineJump.items(from: view.blocks, markdown: view.string)
        #expect(items.map(\.title) == ["First", "Second"])
        #expect(items.map(\.sourceLine) == headings.map(\.id.startLine))
        #expect(items.map(\.level) == [1, 2])

        let second = items[1]
        let heading2 = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == second.sourceLine })
        view.foldStore.toggle(heading2.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.foldStore.isFolded(heading2.id))

        view.jumpToSourceLine(second.sourceLine)

        let map = SourceMap(markdown: fixture)
        let headingBytes = map.offset(ofLine: second.sourceLine)
        let expectedCaret = UTF8NSRange.nsRange(
            utf8Bytes: headingBytes..<(headingBytes + 1),
            in: fixture
        ).location
        #expect(view.selectedUTF16Range.location == expectedCaret)
        #expect(view.selectedUTF16Range.length == 0)
        #expect(view.lastJumpedPackedY == view.y(forSourceLine: second.sourceLine))
        #expect(view.string == fixture)
    }
}

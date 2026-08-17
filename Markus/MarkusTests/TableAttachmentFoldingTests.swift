import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

/// Validates the ticket's N3 acceptance criterion at the layout-manager
/// level: a `TableAttachment` composes with `FoldingTextLayoutFragment`
/// folding. Folding is a layout concern (zero-height owned fragments) —
/// this exercises `FoldingTextLayoutFragment` directly, the same class
/// `FoldingSession` installs in production, rather than going through the
/// full `FoldingTextView`/`FoldingSession` stack. That stack's current
/// `applyStyling` still uses v1's attribute-only styling (blind
/// `setAttributes(_:range:)` over the whole document on every fold
/// toggle), which the Requirements already flag for replacement by
/// ticket 08's paragraph-substitution renderer — an unrelated,
/// soon-to-be-replaced implementation detail this ticket should not
/// entangle itself with. What N3 actually asks is narrower: does the
/// attachment, as a normal character run, break fragment-level folding
/// of the surrounding document? That's what this test proves.
@MainActor
struct TableAttachmentFoldingTests {
    private final class FoldingDelegate: NSObject, NSTextLayoutManagerDelegate {
        weak var contentStorage: NSTextContentStorage?
        var collapsedElementRanges: [NSTextRange] = []

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            let fragment = FoldingTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
            if let elementRange = textElement.elementRange, let contentStorage {
                fragment.isCollapsed = collapsedElementRanges.contains { collapsed in
                    contentStorage.offset(from: collapsed.location, to: elementRange.location) == 0
                }
            }
            return fragment
        }
    }

    private func parsedTable() -> ParsedTable {
        ParsedTable(
            sourceRange: 24..<50,
            alignments: [.left, .right],
            rows: [["A", "B"], ["1", "2"]],
            headerRowIndex: 0
        )
    }

    @Test func foldedParagraphCollapsesToZeroHeightAndTheAttachmentParagraphStaysLaidOut() throws {
        let attachment = TableAttachment(table: parsedTable(), font: PlatformFont.monospaced(size: 14))

        let storage = NSTextStorage()
        storage.append(NSAttributedString(string: "Foldable paragraph one.\n"))
        storage.append(NSAttributedString(string: "Table paragraph: "))
        storage.append(NSAttributedString(attachment: attachment))
        storage.append(NSAttributedString(string: "\n"))
        storage.append(NSAttributedString(string: "Trailing paragraph.\n"))

        let contentStorage = NSTextContentStorage()
        contentStorage.textStorage = storage
        let layoutManager = NSTextLayoutManager()
        let delegate = FoldingDelegate()
        delegate.contentStorage = contentStorage
        layoutManager.delegate = delegate
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container

        // Collapse only the first paragraph's element, mirroring how
        // FoldingSession marks a folded block's fragment.
        var firstElementRange: NSTextRange?
        contentStorage.enumerateTextElements(from: contentStorage.documentRange.location) { element in
            firstElementRange = element.elementRange
            return false
        }
        let unwrappedFirstRange = try #require(firstElementRange)
        delegate.collapsedElementRanges = [unwrappedFirstRange]

        layoutManager.ensureLayout(for: layoutManager.documentRange)

        var fragmentHeights: [CGFloat] = []
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            fragmentHeights.append(fragment.layoutFragmentFrame.height)
            return true
        }

        // Three paragraphs in, three fragments out — the attachment didn't
        // merge, drop, or crash layout of surrounding elements.
        #expect(fragmentHeights.count == 3)

        // The explicitly-folded first paragraph collapses to zero height
        // (N3: folding is zero-height owned fragments).
        #expect(fragmentHeights[0] == 0)

        // Everything else — including the paragraph carrying the table
        // attachment — is unaffected and lays out with real height.
        #expect(fragmentHeights[1] > 0)
        #expect(fragmentHeights[2] > 0)

        // The attachment survived layout unmangled: still present, still
        // carrying its source range, in the one authoritative storage
        // (N4 — nothing was written back or substituted into the buffer;
        // this is the buffer).
        let tableParagraphRange = (storage.string as NSString).range(of: "Table paragraph: ")
        let attachmentIndex = tableParagraphRange.location + tableParagraphRange.length
        let survivingAttachment = try #require(
            storage.attribute(.attachment, at: attachmentIndex, effectiveRange: nil) as? TableAttachment
        )
        #expect(survivingAttachment === attachment)
        #expect(survivingAttachment.sourceRange == parsedTable().sourceRange)
    }
}

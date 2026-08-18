import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

/// Exercises the `NSTextContentStorageDelegate` substitution path
/// (T01): Source mode substitutes nothing and raw bytes lay out
/// unchanged; Preview mode substitutes a rendered paragraph per
/// heading, scaled by level, with markup punctuation absent from the
/// laid-out text. Assertions read what `NSTextContentStorage` actually
/// hands the layout manager (via `enumerateTextElements`), not merely
/// that an attribute was attached to a source range — the mistake this
/// ticket exists to correct (E.14, N9).
@MainActor
struct PreviewSubstitutionTests {
    private func renderedParagraphs(_ view: FoldingTextView) -> [String] {
        var strings: [String] = []
        view.contentStorage.enumerateTextElements(from: view.contentStorage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph {
                strings.append(paragraph.attributedString.string)
            }
            return true
        }
        return strings
    }

    @Test func sourceModeSubstitutesNothingAndRawBytesLayOutUnchanged() throws {
        let markdown = "# Title\n\nBody text.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.source)
        view.ensureLayout()

        let joined = renderedParagraphs(view).joined()
        #expect(joined.contains("# Title"))
        #expect(view.textStorage?.string == markdown)
    }

    @Test func previewModeHidesHeadingMarkupPunctuation() throws {
        let markdown = "# Title\n\nBody text.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = renderedParagraphs(view)
        #expect(paragraphs.contains("Title"))
        #expect(!paragraphs.contains { $0.contains("#") })
        // The buffer itself is never rewritten (N4).
        #expect(view.textStorage?.string == markdown)
    }

    @Test func previewModeScalesHeadingFontByLevelNotAFlat22pt() throws {
        let markdown = "# Title\n\n## Subtitle\n\n###### Tiny\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        var sizeByText: [String: CGFloat] = [:]
        view.contentStorage.enumerateTextElements(from: view.contentStorage.documentRange.location) { element in
            guard let paragraph = element as? NSTextParagraph, paragraph.attributedString.length > 0 else { return true }
            let s = paragraph.attributedString
            if let font = s.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFontType {
                sizeByText[s.string] = font.pointSize
            }
            return true
        }

        let h1 = try #require(sizeByText["Title"])
        let h2 = try #require(sizeByText["Subtitle"])
        let h6 = try #require(sizeByText["Tiny"])
        #expect(h1 > h2)
        #expect(h2 > h6)
    }

    /// Direct proof of the `FoldingSession.applyStyling` blind-restyle
    /// risk flagged in the ticket brief: substitution must survive
    /// theme, zoom, and fold changes because none of it lives on the
    /// buffer that gets blindly re-attributed.
    @Test func substitutionSurvivesThemeZoomAndFoldRoundTrips() throws {
        let markdown = "# Title\n\nBody text.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        view.setTheme(NamedThemeCatalog.tokens(for: .lampblack))
        view.setZoomScale(1.5)
        view.applyFolds()
        view.ensureLayout()

        let paragraphs = renderedParagraphs(view)
        #expect(paragraphs.contains("Title"))
        #expect(!paragraphs.contains { $0.contains("#") })
        #expect(view.textStorage?.string == markdown)
    }

    // MARK: - T02: inline span rendering

    private func attributedParagraphs(_ view: FoldingTextView) -> [NSAttributedString] {
        var strings: [NSAttributedString] = []
        view.contentStorage.enumerateTextElements(from: view.contentStorage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph {
                strings.append(paragraph.attributedString)
            }
            return true
        }
        return strings
    }

    @Test func previewModeAppliesBoldAndItalicWithoutLiteralAsterisks() throws {
        let markdown = "A **bold** word and an *italic* word.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let paragraph = try #require(paragraphs.first { $0.string.contains("bold") })
        #expect(!paragraph.string.contains("*"))
        #expect(paragraph.string.contains("bold"))
        #expect(paragraph.string.contains("italic"))

        let boldRange = (paragraph.string as NSString).range(of: "bold")
        let boldFont = try #require(paragraph.attribute(.font, at: boldRange.location, effectiveRange: nil) as? PlatformFontType)
        #expect(PlatformFont.isBold(boldFont))

        let italicRange = (paragraph.string as NSString).range(of: "italic")
        let italicFont = try #require(paragraph.attribute(.font, at: italicRange.location, effectiveRange: nil) as? PlatformFontType)
        #expect(PlatformFont.isItalic(italicFont))
    }

    @Test func previewModeAppliesStrikethroughWithoutLiteralTildes() throws {
        let markdown = "Strike ~~gone~~ text.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let paragraph = try #require(paragraphs.first { $0.string.contains("gone") })
        #expect(!paragraph.string.contains("~"))
        let goneRange = (paragraph.string as NSString).range(of: "gone")
        let style = paragraph.attribute(.strikethroughStyle, at: goneRange.location, effectiveRange: nil) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
    }

    @Test func previewModeAppliesInlineCodeWithoutLiteralBackticks() throws {
        let markdown = "Some `inline code` here.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let paragraph = try #require(paragraphs.first { $0.string.contains("inline code") })
        #expect(!paragraph.string.contains("`"))
        let range = (paragraph.string as NSString).range(of: "inline code")
        let font = try #require(paragraph.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFontType)
        #expect(PlatformFont.monospaced(size: font.pointSize).fontName == font.fontName)
    }

    @Test func previewModePresentsLinksWithURLAndNoLiteralBracketsOrParens() throws {
        let markdown = "See [the link](https://example.com) for more.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let paragraph = try #require(paragraphs.first { $0.string.contains("the link") })
        #expect(paragraph.string.contains("the link"))
        #expect(!paragraph.string.contains("["))
        #expect(!paragraph.string.contains("]"))
        #expect(!paragraph.string.contains("("))
        #expect(!paragraph.string.contains(")"))

        let range = (paragraph.string as NSString).range(of: "the link")
        let url = paragraph.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        #expect(url == URL(string: "https://example.com"))
    }

    // MARK: - T03: block quotes and lists

    @Test func previewModeShapesBlockQuoteWithIndentAndNoLiteralCaret() throws {
        let markdown = "> Quoted wisdom.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let paragraph = try #require(paragraphs.first { $0.string.contains("Quoted wisdom") })
        #expect(!paragraph.string.contains(">"))
        let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.headIndent ?? 0) > 0)
    }

    @Test func previewModeRendersUnorderedListItemsWithBulletMarkerAndNoLiteralDash() throws {
        let markdown = "- One\n- Two\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let one = try #require(paragraphs.first { $0.string.contains("One") })
        let two = try #require(paragraphs.first { $0.string.contains("Two") })
        #expect(!one.string.hasPrefix("-"))
        #expect(!two.string.hasPrefix("-"))
        #expect(one.string != "One")
        #expect(two.string != "Two")
    }

    @Test func previewModeRendersNestedListItemsAtGreaterIndent() throws {
        let markdown = "- Parent\n  - Child\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let parent = try #require(paragraphs.first { $0.string.contains("Parent") })
        let child = try #require(paragraphs.first { $0.string.contains("Child") })
        #expect(!parent.string.contains("-"))
        #expect(!child.string.contains("-"))

        let parentIndent = (parent.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        let childIndent = (child.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        #expect(childIndent > parentIndent)
    }

    @Test func previewModeDistinguishesCheckedAndUncheckedTaskListItems() throws {
        let markdown = "- [ ] todo\n- [x] done\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let todo = try #require(paragraphs.first { $0.string.contains("todo") })
        let done = try #require(paragraphs.first { $0.string.contains("done") })
        #expect(!todo.string.contains("["))
        #expect(!todo.string.contains("]"))
        #expect(!done.string.contains("["))
        #expect(!done.string.contains("]"))
        // The checked and unchecked markers must actually differ.
        let todoMarker = todo.string.replacingOccurrences(of: "todo", with: "")
        let doneMarker = done.string.replacingOccurrences(of: "done", with: "")
        #expect(todoMarker != doneMarker)
    }

    // MARK: - T04: thematic breaks

    @Test func previewModeDrawsThematicBreakInsteadOfLiteralDashes() throws {
        let markdown = "Before.\n\n---\n\nAfter.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        #expect(!paragraphs.contains { $0.string.contains("-") })

        let ruleParagraph = try #require(paragraphs.first { paragraph in
            var found = false
            paragraph.enumerateAttribute(.attachment, in: NSRange(location: 0, length: paragraph.length)) { value, _, _ in
                if value is ThematicBreakAttachment { found = true }
            }
            return found
        })
        #expect(ruleParagraph.length > 0)
    }

    // MARK: - T05: table integration (ticket 01's TableAttachment)

    @Test func previewModeRendersTableAsAttachmentAndCollapsesItsOtherSourceLines() throws {
        let markdown = """
        Intro.

        | Col | Val |
        |-----|-----|
        | a   | b   |
        | c   | d   |

        After.
        """
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        var foundTableAttachment: TableAttachment?
        var tableParagraphString: String?
        for paragraph in paragraphs {
            paragraph.enumerateAttribute(.attachment, in: NSRange(location: 0, length: paragraph.length)) { value, _, _ in
                if let table = value as? TableAttachment {
                    foundTableAttachment = table
                    tableParagraphString = paragraph.string
                }
            }
        }
        let attachment = try #require(foundTableAttachment)
        #expect(attachment.table.rows.count == 3)
        // The paragraph carrying the table is the attachment itself, not
        // pipe-and-dash source text (R11).
        #expect(!(tableParagraphString ?? "").contains("|"))
        #expect(!(tableParagraphString ?? "").contains("-----"))

        // The table's delimiter/data rows beyond its first line are
        // still present as raw text in the content storage (N4: the
        // buffer — and therefore each paragraph's backing text — is
        // never rewritten) but a reader never sees them: their layout
        // fragments collapse to zero height, the same mechanism as
        // folding (N3).
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.textStorage?.string == markdown)
    }

    // MARK: - T06: fenced code delimiter hiding and image degradation

    @Test func previewModeHidesFenceDelimitersButKeepsCodeContentVisible() throws {
        let markdown = """
        Before.

        ```swift
        let answer = 42
        ```

        After.
        """
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        // No paragraph's laid-out content is a literal fence delimiter —
        // the opening/closing ``` lines are substituted to nothing.
        #expect(!paragraphs.contains { $0.string.contains("```") })
        // The code itself is untouched raw text, still visible (only the
        // delimiters are markup; the content is not).
        #expect(paragraphs.contains { $0.string.contains("let answer = 42") })
        // The blanked delimiter lines collapse to zero height (N3), the
        // buffer itself unchanged (N4).
        #expect(view.collapsedFragmentCount > 0)
        #expect(view.textStorage?.string == markdown)
    }

    @Test func previewModeDegradesImagesToReadableStyledTextNotRawSyntax() throws {
        let markdown = "See ![a red fox](fox.png) here.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let paragraph = try #require(paragraphs.first { $0.string.contains("red fox") })
        #expect(!paragraph.string.contains("!["))
        #expect(!paragraph.string.contains("]("))
        #expect(!paragraph.string.contains(".png"))

        // Styled, not blended in as plain body text: readers should be
        // able to tell this was an image (R12: degrade to readable
        // styled text, not raw syntax, and not a rendered image).
        let range = (paragraph.string as NSString).range(of: "red fox")
        let font = try #require(paragraph.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFontType)
        #expect(PlatformFont.isItalic(font))
    }

    // MARK: - T07: fixture composition — every covered element together

    @Test func previewModeRendersEveryCoveredGFMElementAsAReaderWouldSeeIt() throws {
        let markdown = GFMPreviewFixture.markdown
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        let joined = paragraphs.map(\.string).joined(separator: "\n")

        // Headings: text survives, marker punctuation does not.
        #expect(joined.contains("Title"))
        #expect(joined.contains("Subtitle"))
        #expect(!joined.contains("# Title"))
        #expect(!joined.contains("## Subtitle"))

        // Bold/italic: words survive, asterisks do not.
        #expect(joined.contains("bold"))
        #expect(joined.contains("italic"))
        #expect(!joined.contains("**bold**"))
        #expect(!joined.contains("*italic*"))

        // Image: alt text survives as a styled placeholder, raw syntax does not.
        #expect(joined.contains("red fox"))
        #expect(!joined.contains("!["))
        #expect(!joined.contains("](fox.png)"))

        // Block quote: body survives, leading `>` does not.
        #expect(joined.contains("A block quote with a note inside it."))
        #expect(!joined.contains("> A block quote"))

        // Thematic break: drawn as a rule attachment, never literal dashes.
        // (Checked via the attachment, not "no paragraph contains a dash" —
        // the table's collapsed header-separator row is a hidden but still
        // enumerable paragraph whose raw text legitimately contains "---".)
        let ruleParagraph = try #require(paragraphs.first { paragraph in
            var found = false
            paragraph.enumerateAttribute(.attachment, in: NSRange(location: 0, length: paragraph.length)) { value, _, _ in
                if value is ThematicBreakAttachment { found = true }
            }
            return found
        })
        #expect(ruleParagraph.length > 0)

        // Nested list: both levels' text survive, marker dashes do not.
        #expect(joined.contains("Outer item"))
        #expect(joined.contains("Nested item"))
        #expect(!joined.contains("- Outer item"))
        #expect(!joined.contains("  - Nested item"))

        // Strikethrough / inline code / link: text survives, markup does not.
        #expect(joined.contains("gone"))
        #expect(joined.contains("inline"))
        #expect(joined.contains("link"))
        #expect(!joined.contains("~~gone~~"))
        #expect(!joined.contains("`inline`"))
        #expect(!joined.contains("[link]("))

        // Task list: checkbox text survives, raw `[ ]`/`[x]` syntax does not.
        #expect(joined.contains("unchecked"))
        #expect(joined.contains("checked"))
        #expect(!joined.contains("- [ ]"))
        #expect(!joined.contains("- [x]"))

        // Fenced code: delimiters absent, code content still visible.
        #expect(!joined.contains("```"))
        #expect(joined.contains("let answer = 42"))
        #expect(joined.contains("graph TD"))

        // Table: renders via the real TableAttachment, not literal pipes.
        var foundTableAttachment: TableAttachment?
        for paragraph in paragraphs {
            paragraph.enumerateAttribute(.attachment, in: NSRange(location: 0, length: paragraph.length)) { value, _, _ in
                if let table = value as? TableAttachment { foundTableAttachment = table }
            }
        }
        #expect(foundTableAttachment != nil)
        #expect(!joined.contains("| Col | Val |"))

        // Source mode round-trips the raw bytes unchanged (N4) regardless
        // of how much Preview mode substituted.
        view.setMode(.source)
        view.ensureLayout()
        #expect(view.textStorage?.string == markdown)
        #expect(DocumentSave.writeUTF8(from: try #require(view.textStorage)) == Data(markdown.utf8))
    }

    // MARK: - Regression: an empty ATX heading must not reach TextKit 2
    // as a zero-length substitution (the same hazard class T06's fence
    // delimiters hit — see `PreviewElement.init`).

    @Test func previewModeHandlesAnEmptyHeadingWithoutHangingOrLeavingItVisible() throws {
        let markdown = "# \n\nBody text.\n"
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let paragraphs = attributedParagraphs(view)
        // The empty heading's own line never shows literal "#" markup,
        // and the following body text still renders normally — proves
        // ensureLayout() actually completed (this test would hang
        // instead of failing if PreviewElement's zero-length guard
        // regressed, exactly as T06's fence-delimiter bug did).
        #expect(!paragraphs.contains { $0.string.contains("#") })
        #expect(paragraphs.contains { $0.string.contains("Body text.") })
        #expect(view.textStorage?.string == markdown)
    }

    // MARK: - Zero parses on fold/theme/zoom/mode-switch/resize (T03, P3)

    @Test func styleOnlyChangesNeverReparseButARealTextChangeDoes() throws {
        let markdown = """
        ## Heading two

        A paragraph under the H2.

        ```swift
        let answer = 42
        ```
        """
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let afterLoad = view.session.parsesPerformed
        #expect(afterLoad > 0)

        let heading = try #require(view.blocks.first { $0.id.kind == .heading })
        view.toggleFold(atSourceLine: heading.id.startLine)
        #expect(view.session.parsesPerformed == afterLoad)

        view.setTheme(.default)
        #expect(view.session.parsesPerformed == afterLoad)

        view.setZoomScale(1.3)
        #expect(view.session.parsesPerformed == afterLoad)

        view.setMode(.source)
        #expect(view.session.parsesPerformed == afterLoad)
        view.setMode(.preview)
        #expect(view.session.parsesPerformed == afterLoad)

        // Container resize (the same path `layout()`/`layoutSubviews()`
        // drive) must not reparse either.
        view.frame = CGRect(x: 0, y: 0, width: 700, height: 800)
        view.ensureLayout()
        #expect(view.session.parsesPerformed == afterLoad)

        // Preview rendering must still be correct after all those
        // style-only changes reused the cached structure — not just the
        // counter staying flat, the actual output too.
        let paragraphs = attributedParagraphs(view)
        #expect(paragraphs.contains { $0.string.contains("Heading two") })
        #expect(!paragraphs.contains { $0.string.contains("##") })

        // A real text change still reparses — proves the counter is a
        // live assertion that can fail, not a constant (N9).
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        #expect(view.replaceSelection(with: "Extra text.\n\n"))
        #expect(view.session.parsesPerformed == afterLoad + 1)
    }
}

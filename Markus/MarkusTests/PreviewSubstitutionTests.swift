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
        #expect(font.isFixedPitch || PlatformFont.monospaced(size: font.pointSize).fontName == font.fontName)
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
}

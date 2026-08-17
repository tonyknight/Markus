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
}

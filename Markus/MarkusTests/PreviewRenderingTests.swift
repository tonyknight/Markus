import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct PreviewRenderingTests {
    @Test func previewPaintsGFMAttributesOnTheSourceBuffer() throws {
        let markdown = GFMPreviewFixture.markdown
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)
        view.ensureLayout()

        let storage = try #require(view.textStorage)
        #expect(storage.string == markdown)
        #expect(DocumentSave.writeUTF8(from: storage) == Data(markdown.utf8))

        func nsRange(of substring: String) -> NSRange {
            (markdown as NSString).range(of: substring)
        }

        let headingRange = nsRange(of: "# Title")
        let tableRange = nsRange(of: "| Col | Val |")
        let taskRange = nsRange(of: "- [ ] unchecked")
        let strikeRange = nsRange(of: "gone")
        let footnoteRange = nsRange(of: "[^1]: Footnote body.")
        let fenceRange = nsRange(of: "let answer = 42")
        let linkRange = nsRange(of: "link")
        let inlineRange = nsRange(of: "inline")
        let mathRange = nsRange(of: "$x$")
        let mermaidRange = nsRange(of: "graph TD")

        #expect(attribute(.markdownSpanKind, at: headingRange, in: storage) as? MarkdownSpanKind == .heading(level: 1))
        #expect(attribute(.markdownSpanKind, at: tableRange, in: storage) as? MarkdownSpanKind == .table)
        #expect(attribute(.markdownSpanKind, at: taskRange, in: storage) as? MarkdownSpanKind == .taskListItem)
        #expect(attribute(.markdownSpanKind, at: strikeRange, in: storage) as? MarkdownSpanKind == .strikethrough)
        #expect(attribute(.strikethroughStyle, at: strikeRange, in: storage) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attribute(.markdownSpanKind, at: footnoteRange, in: storage) as? MarkdownSpanKind == .footnote)
        #expect(attribute(.markdownSpanKind, at: fenceRange, in: storage) as? MarkdownSpanKind == .fencedCode)
        #expect(attribute(.markdownSpanKind, at: linkRange, in: storage) as? MarkdownSpanKind == .link)
        #expect(attribute(.markdownSpanKind, at: inlineRange, in: storage) as? MarkdownSpanKind == .inlineCode)

        #expect(attribute(.markdownSpanKind, at: mathRange, in: storage) as? MarkdownSpanKind == nil)
        #expect(attribute(.markdownSpanKind, at: mermaidRange, in: storage) as? MarkdownSpanKind == .fencedCode)

        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine == 1 })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.collapsedFragmentCount > 0)
        #expect(storage.string == markdown)
        #expect(!usesCollapsedParagraphStyles(storage))
    }

    private func attribute(_ name: NSAttributedString.Key, at range: NSRange, in storage: NSTextStorage) -> Any? {
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return storage.attribute(name, at: range.location, effectiveRange: nil)
    }

    private func usesCollapsedParagraphStyles(_ storage: NSTextStorage) -> Bool {
        var found = false
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            guard let style = value as? NSParagraphStyle else { return }
            if style.maximumLineHeight > 0, style.maximumLineHeight <= 0.02 {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

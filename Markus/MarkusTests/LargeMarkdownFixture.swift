import Foundation

/// Deterministic large-document generators for performance tests
/// (T05). No large-document fixture existed anywhere in the suite
/// before this ticket. Mixes headings, paragraphs, lists, and fenced
/// code — realistic document structure at scale, not one giant
/// paragraph — so the read-path performance tests exercise the same
/// kind of block variety `BlockIndex`/`PreviewStructureCollector`
/// handle in a real document.
enum LargeMarkdownFixture {
    /// Builds Markdown at least `targetBytes` UTF-8 bytes long by
    /// repeating a fixed-shape "section" (heading, paragraph, list,
    /// and — every fifth section — a fenced code block) until the
    /// target size is reached.
    static func markdown(atLeastBytes targetBytes: Int) -> String {
        var output = String()
        output.reserveCapacity(targetBytes + 4_096)
        var section = 0
        while output.utf8.count < targetBytes {
            section += 1
            output += "## Section \(section)\n\n"
            output += "This is paragraph \(section) of a large fixture document, written to exercise realistic Markdown structure at scale rather than one giant paragraph. It has enough words to read like ordinary prose.\n\n"
            output += "- item one for section \(section)\n"
            output += "- item two for section \(section)\n"
            output += "- item three for section \(section)\n\n"
            if section.isMultiple(of: 5) {
                output += "```swift\nlet value\(section) = \(section)\nprint(value\(section))\n```\n\n"
            }
        }
        return output
    }

    /// Read-path figures (load, fold, bulk fold/unfold) apply to a
    /// saved 5 MB Markdown fixture per the Performance budgets table.
    static let fiveMegabytes = markdown(atLeastBytes: 5 * 1024 * 1024)

    /// Typing figures apply to a 1 MB fixture per the Performance
    /// budgets table.
    static let oneMegabyte = markdown(atLeastBytes: 1 * 1024 * 1024)
}

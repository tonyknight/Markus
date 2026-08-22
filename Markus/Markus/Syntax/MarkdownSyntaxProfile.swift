import Foundation

/// Markdown profile: today’s cmark `BlockIndex` heading/fence folds and
/// `OutlineJump` heading rows. Diagnostics and highlight spans are empty
/// here (v1.4 data hook; no inspector UI).
struct MarkdownSyntaxProfile: SyntaxProfile {
    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let foldables = BlockIndex.build(markdown: buffer)
        return SyntaxAnalysis(
            foldables: foldables,
            outlineRows: OutlineJump.items(from: foldables, markdown: buffer),
            diagnostics: [],
            highlightSpans: []
        )
    }
}

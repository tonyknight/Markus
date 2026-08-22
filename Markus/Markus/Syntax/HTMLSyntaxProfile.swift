import Foundation

/// Shared HTML/SVG profile: one tokenizer, dialect chooses HTML5 vs XML
/// matching. Analyze uses `HTMLScanBudget.default` so a multi-MB file
/// cannot freeze typing (N2).
struct HTMLSyntaxProfile: SyntaxProfile {
    var dialect: HTMLScanDialect

    static let html = HTMLSyntaxProfile(dialect: .html)
    static let svg = HTMLSyntaxProfile(dialect: .xml)

    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let result = HTMLScanner.scan(buffer, dialect: dialect, budget: .default)
        return SyntaxAnalysis(
            foldables: result.foldables,
            outlineRows: result.outlineRows,
            diagnostics: result.diagnostics,
            highlightSpans: result.highlightSpans
        )
    }
}

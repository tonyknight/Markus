import Foundation

/// TOML profile: table / array-of-tables folds, outline rows, parse
/// diagnostics, and cheap key/string/comment/number spans. Analyze uses
/// `TOMLScanBudget.default` so a multi-MB file cannot freeze typing (N2).
struct TOMLSyntaxProfile: SyntaxProfile {
    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let result = TOMLScanner.scan(buffer, budget: .default)
        return SyntaxAnalysis(
            foldables: result.foldables,
            outlineRows: result.outlineRows,
            diagnostics: result.diagnostics,
            highlightSpans: result.highlightSpans
        )
    }
}

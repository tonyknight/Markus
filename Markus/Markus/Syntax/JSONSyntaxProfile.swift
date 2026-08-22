import Foundation

/// JSON profile: object/array folds, outline rows, parse diagnostics,
/// and cheap string/number/keyword spans. Save is the UTF-8 buffer (N6);
/// this profile never pretty-prints. Analyze uses `JSONScanBudget.default`
/// so a multi-MB file cannot freeze typing (N2).
struct JSONSyntaxProfile: SyntaxProfile {
    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let result = JSONScanner.scan(buffer, budget: .default)
        return SyntaxAnalysis(
            foldables: result.foldables,
            outlineRows: result.outlineRows,
            diagnostics: result.diagnostics,
            highlightSpans: result.highlightSpans
        )
    }
}

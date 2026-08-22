import Foundation

/// Shell profile: keyword/string/comment/number spans and best-effort
/// `{…}` folds. Analyze uses `ShellScanBudget.default` so a multi-MB
/// file cannot freeze typing (N2). Indent folds are not attempted.
struct ShellSyntaxProfile: SyntaxProfile {
    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let result = ShellScanner.scan(buffer, budget: .default)
        return SyntaxAnalysis(
            foldables: result.foldables,
            outlineRows: result.outlineRows,
            diagnostics: result.diagnostics,
            highlightSpans: result.highlightSpans
        )
    }
}

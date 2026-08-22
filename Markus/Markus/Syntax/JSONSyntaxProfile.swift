import Foundation

/// JSON profile: object/array folds, outline rows, parse diagnostics,
/// and cheap string/number/keyword spans. Save is the UTF-8 buffer (N6);
/// this profile never pretty-prints.
struct JSONSyntaxProfile: SyntaxProfile {
    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let result = JSONScanner.scan(buffer)
        return SyntaxAnalysis(
            foldables: result.foldables,
            outlineRows: result.outlineRows,
            diagnostics: result.diagnostics,
            highlightSpans: result.highlightSpans
        )
    }
}

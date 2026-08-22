import Foundation

/// Brace-language profile for CSS, JavaScript/TypeScript, Swift, and PHP.
/// Analyze uses `BraceScanBudget.default` so a multi-MB file cannot freeze
/// typing (N2). `.tsx` is TypeScript kind; JSX tags are not fold units.
/// PHP folds `{` blocks only — not HTML islands or `<?php` tags.
struct BraceSyntaxProfile: SyntaxProfile {
    var dialect: BraceDialect

    static let css = BraceSyntaxProfile(dialect: .css)
    static let javascript = BraceSyntaxProfile(dialect: .javascript)
    static let swift = BraceSyntaxProfile(dialect: .swift)
    static let php = BraceSyntaxProfile(dialect: .php)

    func analyze(_ buffer: String) -> SyntaxAnalysis {
        let result = BraceScanner.scan(buffer, dialect: dialect, budget: .default)
        return SyntaxAnalysis(
            foldables: result.foldables,
            outlineRows: result.outlineRows,
            diagnostics: result.diagnostics,
            highlightSpans: result.highlightSpans
        )
    }
}

import Foundation

/// Per-kind syntax analysis that feeds the same `FoldStore` / outline /
/// (v1.4) diagnostics / inner-color spans. Markdown wraps today’s
/// `BlockIndex`; JSON uses `JSONSyntaxProfile`; HTML and SVG share
/// `HTMLSyntaxProfile`; TOML uses `TOMLSyntaxProfile`; CSS / JS / TS /
/// Swift / PHP use `BraceSyntaxProfile`. Shell stays empty until
/// its ticket.
protocol SyntaxProfile: Sendable {
    func analyze(_ buffer: String) -> SyntaxAnalysis
}

/// Foldables, outline rows, parse diagnostics, and highlight spans for
/// one buffer snapshot.
struct SyntaxAnalysis: Equatable, Sendable {
    var foldables: [Block]
    var outlineRows: [OutlineItem]
    var diagnostics: [ParseDiagnostic]
    var highlightSpans: [HighlightSpan]

    static let empty = SyntaxAnalysis(
        foldables: [],
        outlineRows: [],
        diagnostics: [],
        highlightSpans: []
    )
}

/// Parse diagnostic held as data for v1.4 Inspector. No warnings UI here.
struct ParseDiagnostic: Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
        case error
        case warning
        case info
    }

    var line: Int
    var message: String
    var severity: Severity
}

/// Inner-color span. Roles map through `CodeColorRoles` from existing `ThemeTokens`.
struct HighlightSpan: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case keyword
        case string
        case comment
        case number
    }

    var bytes: Range<Int>
    var role: Role
}

/// Empty analysis for kinds that do not have a profile yet.
struct EmptySyntaxProfile: SyntaxProfile {
    func analyze(_ buffer: String) -> SyntaxAnalysis {
        .empty
    }
}

enum SyntaxProfiles {
    static func profile(for kind: DocumentKind) -> any SyntaxProfile {
        switch kind {
        case .markdown:
            MarkdownSyntaxProfile()
        case .json:
            JSONSyntaxProfile()
        case .html:
            HTMLSyntaxProfile.html
        case .svg:
            HTMLSyntaxProfile.svg
        case .toml:
            TOMLSyntaxProfile()
        case .css:
            BraceSyntaxProfile.css
        case .javascript, .typescript:
            BraceSyntaxProfile.javascript
        case .swift:
            BraceSyntaxProfile.swift
        case .php:
            BraceSyntaxProfile.php
        default:
            EmptySyntaxProfile()
        }
    }
}

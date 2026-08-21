import Foundation

/// GitHub-style alert kinds (`> [!NOTE]`, TIP, WARNING, IMPORTANT, CAUTION).
/// Detection is first-line-only and known-types-only so ordinary block
/// quotes are never promoted to callouts.
enum GitHubAlertType: String, Equatable, Sendable, CaseIterable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    var label: String { rawValue }

    var symbolName: String {
        switch self {
        case .note: "info.circle"
        case .tip: "lightbulb"
        case .important: "exclamationmark.bubble"
        case .warning: "exclamationmark.triangle"
        case .caution: "exclamationmark.octagon"
        }
    }

    /// `markerLine` is the first line of a blockquote (plain text up to
    /// the first break, trimmed). Returns a type only for the five
    /// known alerts. `[!FOO]` and anything that is not exactly `[!TYPE]`
    /// return `nil`.
    static func parse(markerLine: String) -> GitHubAlertType? {
        guard looksLikeAlertMarker(markerLine) else { return nil }
        let inner = innerWord(of: markerLine)
        return GitHubAlertType(rawValue: inner)
    }

    /// True when the first line is `[!WORD]` (optional inner whitespace).
    /// Known types still need `parse`; unknown `[!FOO]` is a quote.
    static func looksLikeAlertMarker(_ markerLine: String) -> Bool {
        let trimmed = markerLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), trimmed.hasSuffix("]"), trimmed.count >= 4 else {
            return false
        }
        let inner = innerWord(of: markerLine)
        return !inner.isEmpty && inner.allSatisfy(\.isLetter)
    }

    private static func innerWord(of markerLine: String) -> String {
        let trimmed = markerLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), trimmed.hasSuffix("]") else { return "" }
        return trimmed.dropFirst(2).dropLast()
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
    }
}

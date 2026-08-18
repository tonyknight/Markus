import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Bridges Preview substitution into TextKit 2's layout path.
/// `NSTextContentStorage` asks this delegate for each paragraph as it
/// is about to be laid out; in Preview mode, with a substitution
/// available at that paragraph's start offset, this returns a rendered
/// `NSTextParagraph` in its place — never writing back to
/// `NSTextStorage` (N4). In Source mode, or when no substitution
/// applies (an unhandled block kind, or a continuation line of a
/// multi-line element — hidden separately via
/// `FoldingTextLayoutFragment.isCollapsed`, not here), this returns
/// `nil` and the default raw text lays out unchanged.
@MainActor
final class PreviewContentStorageDelegate: NSObject, NSTextContentStorageDelegate {
    var isPreviewMode = false
    var index: PreviewSubstitutionIndex?

    /// N8 counter ("paragraphs substituted"): counts every successful
    /// (non-nil) substitution query. `NSTextContentStorage` only calls
    /// this delegate for paragraphs it is actually about to lay out, so
    /// bounding draw-time fragment enumeration to the viewport (T01)
    /// bounds this too — proving P4's "substitution is lazy and
    /// per-element" empirically rather than by inspection.
    private(set) var substitutionQueryCount = 0

    func resetSubstitutionQueryCount() {
        substitutionQueryCount = 0
    }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard isPreviewMode, let index else { return nil }
        guard let rendered = index.substitution(atUTF16Offset: range.location) else { return nil }
        substitutionQueryCount += 1
        return NSTextParagraph(attributedString: rendered)
    }
}

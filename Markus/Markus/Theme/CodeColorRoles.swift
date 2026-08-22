import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Inner code colors derived from existing Markdown `ThemeTokens`.
/// No new Appearance wells; ThemeStore persistence is unchanged (R10).
struct CodeColorRoles {
    var keyword: PlatformColorType
    var string: PlatformColorType
    var comment: PlatformColorType
    var number: PlatformColorType

    /// keyword ← link, string ← fence, number ← inlineCode, comment ← italic.
    init(_ tokens: ThemeTokens) {
        keyword = tokens.link
        string = tokens.fence
        comment = tokens.italic
        number = tokens.inlineCode
    }
}

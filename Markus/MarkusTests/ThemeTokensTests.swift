import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct ThemeTokensTests {
    @Test func swappingATokenRecolorsTheMatchingPreviewRange() throws {
        let markdown = GFMPreviewFixture.markdown
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)

        let storage = try #require(view.textStorage)
        let headingRange = (markdown as NSString).range(of: "# Title")
        let linkRange = (markdown as NSString).range(of: "[link](https://example.com)")
        let bodyRange = (markdown as NSString).range(of: "Math is")

        let originalHeading = storage.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? PlatformColorType
        #expect(originalHeading?.isEqual(ThemeTokens.default.heading) == true)
        #expect((storage.attribute(.foregroundColor, at: bodyRange.location, effectiveRange: nil) as? PlatformColorType)?
            .isEqual(ThemeTokens.default.body) == true)

        var tokens = ThemeTokens.default
        #if os(macOS)
        tokens.heading = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        tokens.link = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
        #else
        tokens.heading = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        tokens.link = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        #endif
        #expect(!tokens.heading.isEqual(ThemeTokens.default.heading))

        view.setTheme(tokens)

        #expect((storage.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? PlatformColorType)?
            .isEqual(tokens.heading) == true)
        #expect((storage.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? PlatformColorType)?
            .isEqual(tokens.link) == true)
        #expect((storage.attribute(.foregroundColor, at: bodyRange.location, effectiveRange: nil) as? PlatformColorType)?
            .isEqual(tokens.body) == true)
        #expect(storage.string == markdown)
    }
}

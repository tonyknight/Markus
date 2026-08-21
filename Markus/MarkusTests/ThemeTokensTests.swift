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
    @Test func catalogExposesSixFamiliesAndTwoVariants() {
        #expect(ThemeFamily.allCases.count == 6)
        #expect(ThemeFamily.allCases.map(\.rawValue) == [
            "nord", "monokai", "solarized", "github", "catppuccin", "gruvbox",
        ])
        #expect(ThemeFamily.allCases.map(\.displayName) == [
            "Nord", "Monokai", "Solarized", "GitHub", "Catppuccin", "Gruvbox",
        ])
        #expect(ThemeVariant.allCases.map(\.rawValue) == ["light", "dark"])
        #expect(ThemeVariant.allCases.map(\.displayName) == ["Light", "Dark"])
    }

    @Test func namedPalettesAreDistinctAndFillEveryToken() {
        var seen: [ThemeTokens] = []
        for family in ThemeFamily.allCases {
            let light = NamedThemeCatalog.tokens(for: family, variant: .light)
            let dark = NamedThemeCatalog.tokens(for: family, variant: .dark)
            #expect(light != dark)
            for tokens in [light, dark] {
                #expect(tokens.background.cgColor.alpha > 0)
                #expect(tokens.heading.cgColor.alpha > 0)
                #expect(tokens.body.cgColor.alpha > 0)
                #expect(tokens.link.cgColor.alpha > 0)
                #expect(tokens.inlineCode.cgColor.alpha > 0)
                #expect(tokens.fence.cgColor.alpha > 0)
                #expect(tokens.list.cgColor.alpha > 0)
                #expect(tokens.foldMarker.cgColor.alpha > 0)
                #expect(tokens.table.cgColor.alpha > 0)
                #expect(tokens.strikethrough.cgColor.alpha > 0)
                #expect(tokens.footnote.cgColor.alpha > 0)
                for previous in seen {
                    #expect(tokens != previous)
                }
                seen.append(tokens)
            }
        }
        #expect(seen.count == 12)
        #expect(NamedThemeCatalog.tokens(for: .nord, variant: .light) == ThemeTokens.default)
    }

    @Test func setThemeAppliesNamedPaletteHeadingAndBodyColors() throws {
        let markdown = GFMPreviewFixture.markdown
        let view = FoldingTextView()
        view.loadMarkdown(markdown)
        view.setMode(.preview)

        let storage = try #require(view.textStorage)
        let headingRange = (markdown as NSString).range(of: "# Title")
        let bodyRange = (markdown as NSString).range(of: "Math is")
        let lampblack = NamedThemeCatalog.tokens(for: .nord, variant: .dark)
        #expect(lampblack != ThemeTokens.default)

        view.setTheme(lampblack)

        #expect((storage.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? PlatformColorType)?
            .isEqual(lampblack.heading) == true)
        #expect((storage.attribute(.foregroundColor, at: bodyRange.location, effectiveRange: nil) as? PlatformColorType)?
            .isEqual(lampblack.body) == true)
        #expect(view.tokens == lampblack)
    }

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

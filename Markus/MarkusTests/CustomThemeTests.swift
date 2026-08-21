import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

@MainActor
struct CustomThemeTests {
    @Test func changingBackgroundOrTextStyleYieldsDifferentTokens() {
        let paper = srgb(0.96, 0.94, 0.88)
        let slate = srgb(0.12, 0.14, 0.18)
        let lightPaper = CustomTheme.tokens(background: paper, textStyle: .light)
        let darkPaper = CustomTheme.tokens(background: paper, textStyle: .dark)
        let lightSlate = CustomTheme.tokens(background: slate, textStyle: .light)

        #expect(lightPaper != darkPaper)
        #expect(lightPaper != lightSlate)
        #expect(lightPaper.background.isEqual(paper))
        #expect(lightSlate.background.isEqual(slate))
        #expect(!lightPaper.body.isEqual(darkPaper.body))
        #expect(!lightPaper.h1.isEqual(darkPaper.h1))
        #expect(!lightPaper.link.isEqual(darkPaper.link))
    }

    @Test func autoFollowsBackgroundLuminance() {
        let lightBG = srgb(0.97, 0.97, 0.95)
        let darkBG = srgb(0.08, 0.09, 0.10)
        let autoLight = CustomTheme.tokens(background: lightBG, textStyle: .auto)
        let explicitLight = CustomTheme.tokens(background: lightBG, textStyle: .light)
        let autoDark = CustomTheme.tokens(background: darkBG, textStyle: .auto)
        let explicitDark = CustomTheme.tokens(background: darkBG, textStyle: .dark)

        #expect(autoLight == explicitLight)
        #expect(autoDark == explicitDark)
        #expect(autoLight != autoDark)
        #expect(CustomTheme.resolvedTextStyle(background: lightBG, textStyle: .auto) == .light)
        #expect(CustomTheme.resolvedTextStyle(background: darkBG, textStyle: .auto) == .dark)
        #expect(CustomTheme.resolvedTextStyle(background: lightBG, textStyle: .dark) == .dark)
    }

    private func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformColorType {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

#if os(macOS)
import AppKit
import SwiftUI

/// The Mac main menu's File/Edit content, built as SwiftUI `Commands`
/// rather than an imperative `NSMenu` assigned to `NSApp.mainMenu`.
///
/// History: `MacMainMenu.build()` (still present, now otherwise unused)
/// built a real `NSMenu` and installed it via `NSApp.mainMenu = ...` in
/// `MarkusAppDelegate`. That lost a race against SwiftUI's own
/// Scene/Commands machinery, which reinstalls its own default menu
/// (visible as "Markus / View / Window / Help" with **no File or Edit
/// menu at all**) at multiple points during and after launch — not just
/// once at startup. Fighting that by reasserting `NSApp.mainMenu`
/// imperatively (even deferred to the next run loop turn) was observed
/// to still lose, repeatedly, in a real running build. Declaring the
/// same content as `Commands` instead means SwiftUI installs it as part
/// of *its own* menu-building pass, so there is nothing left to race.
///
/// Every action still targets `nil` and dispatches via
/// `NSApp.sendAction(_:to:from:)`, resolving through the responder chain
/// to `MarkdownDocumentViewController`/`NSDocument`/`NSDocumentController`
/// exactly as the old `NSMenu`-based items did — no change to how the
/// actions themselves are implemented or found.
struct MarkusCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Settings\u{2026}") {
                SettingsWindowChrome.open(openWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("New") {
                NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New JSON") {
                _ = try? MacDocumentLaunch.openUntitledDocument(ofType: DocumentKind.json.typeName)
            }
            Button("New HTML") {
                _ = try? MacDocumentLaunch.openUntitledDocument(ofType: DocumentKind.html.typeName)
            }
            Button("New SVG") {
                _ = try? MacDocumentLaunch.openUntitledDocument(ofType: DocumentKind.svg.typeName)
            }
            Button("New TOML") {
                _ = try? MacDocumentLaunch.openUntitledDocument(ofType: DocumentKind.toml.typeName)
            }

            Button("Open\u{2026}") {
                NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            // Cmd+Shift+F, not Cmd+Shift+O: the title bar keeps its
            // Cmd+Shift+O "Outline" jump button, so Open Folder needs a
            // different shortcut to avoid colliding.
            Button("Open Folder\u{2026}") {
                NSApp.sendAction(MacMainMenuAction.performOpenFolder, to: nil, from: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Menu("Open Recent") {
                let urls = NSDocumentController.shared.recentDocumentURLs
                if urls.isEmpty {
                    Text("No Recent Documents")
                } else {
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                        Button(url.lastPathComponent) {
                            _ = try? MacDocumentLaunch.openFile(url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }

            Divider()

            Button("Save") {
                NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Close") {
                NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Find") {
                NSApp.sendAction(MacMainMenuAction.performFind, to: nil, from: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Go to Line") {
                NSApp.sendAction(MacMainMenuAction.performGoToLine, to: nil, from: nil)
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Fold All") {
                NSApp.sendAction(MacMainMenuAction.performFoldAll, to: nil, from: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Unfold All") {
                NSApp.sendAction(MacMainMenuAction.performUnfoldAll, to: nil, from: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
        }

        CommandMenu("Format") {
            Menu("Document Kind") {
                ForEach(DocumentKind.waveA, id: \.self) { kind in
                    Button(kind.displayName) {
                        Self.sendSetKind(kind)
                    }
                }
            }
            Divider()
            Button("Pin Kind") {
                NSApp.sendAction(MacMainMenuAction.pinDocumentKind, to: nil, from: nil)
            }
            Button("Unpin Kind") {
                NSApp.sendAction(MacMainMenuAction.unpinDocumentKind, to: nil, from: nil)
            }
        }
    }

    private static func sendSetKind(_ kind: DocumentKind) {
        let selector: Selector
        switch kind {
        case .markdown: selector = MacMainMenuAction.setDocumentKindMarkdown
        case .json: selector = MacMainMenuAction.setDocumentKindJSON
        case .html: selector = MacMainMenuAction.setDocumentKindHTML
        case .svg: selector = MacMainMenuAction.setDocumentKindSVG
        case .toml: selector = MacMainMenuAction.setDocumentKindTOML
        default: return
        }
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
#endif

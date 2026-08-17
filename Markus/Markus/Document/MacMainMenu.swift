#if os(macOS)
import AppKit

/// Selector names for the custom Edit/File actions that resolve through
/// the responder chain to `MarkdownDocument` (implemented alongside the
/// menu-routing task). Built as plain `Selector`s rather than `#selector`
/// so this file does not need to know the implementing type's method
/// bodies exist yet — Objective-C dispatch resolves them by name.
enum MacMainMenuAction {
    static let performOpenFolder = Selector(("performOpenFolder:"))
    static let performFind = Selector(("performFind:"))
    static let performGoToLine = Selector(("performGoToLine:"))
    static let performFoldAll = Selector(("performFoldAll:"))
    static let performUnfoldAll = Selector(("performUnfoldAll:"))
    static let openRecentDocument = #selector(RecentDocumentsMenuDelegate.openRecentDocument(_:))
}

/// Populates the "Open Recent" submenu from `NSDocumentController`'s own
/// `recentDocumentURLs` each time the menu is about to open, and opens
/// the chosen document through the same `MacDocumentLaunch` path used
/// elsewhere (so it creates a proper tabbable `NSDocument` window).
final class RecentDocumentsMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items = MacMainMenu.recentDocumentItems(for: NSDocumentController.shared.recentDocumentURLs)
    }

    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        _ = try? MacDocumentLaunch.openFile(url)
    }
}

/// Builds the AppKit main menu: File (New, Open…, Open Folder…, Open
/// Recent, Save) and Edit (Find, Go to Line, Fold All, Unfold All).
/// Standard document actions target `nil` and resolve via
/// `NSDocumentController`/`NSDocument`'s automatic responder-chain
/// wiring; custom actions target `nil` and resolve to `MarkdownDocument`,
/// which sits in the responder chain as the active document.
enum MacMainMenu {
    @MainActor
    static func build() -> NSMenu {
        let main = NSMenu(title: "Markus")
        main.addItem(appMenuItem())
        main.addItem(fileMenuItem())
        main.addItem(editMenuItem())
        return main
    }

    // MARK: App menu

    private static func appMenuItem() -> NSMenuItem {
        let appName = ProcessInfo.processInfo.processName
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)
        menu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        return item
    }

    // MARK: File menu

    private static func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")

        menu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        menu.addItem(withTitle: "Open\u{2026}", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        let openFolder = menu.addItem(withTitle: "Open Folder\u{2026}", action: MacMainMenuAction.performOpenFolder, keyEquivalent: "o")
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        openFolder.target = nil

        menu.addItem(openRecentMenuItem())
        menu.addItem(.separator())

        menu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")

        item.submenu = menu
        return item
    }

    private static func openRecentMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Open Recent")
        submenu.delegate = RecentDocumentsMenuDelegate.shared
        item.submenu = submenu
        return item
    }

    /// Builds the "Open Recent" submenu contents from `urls`, in the shape
    /// AppKit's own recent-documents menus use: one item per URL (newest
    /// first, as `NSDocumentController` already orders them), then a
    /// separator and "Clear Menu". A pure function so tests can assert its
    /// output without mutating the user's real, persisted recent-documents
    /// list.
    static func recentDocumentItems(for urls: [URL]) -> [NSMenuItem] {
        guard !urls.isEmpty else {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return [empty]
        }
        var items = urls.map { url -> NSMenuItem in
            let item = NSMenuItem(title: url.lastPathComponent, action: MacMainMenuAction.openRecentDocument, keyEquivalent: "")
            item.representedObject = url
            item.target = RecentDocumentsMenuDelegate.shared
            return item
        }
        items.append(.separator())
        items.append(NSMenuItem(
            title: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        ))
        return items
    }

    // MARK: Edit menu

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Find", action: MacMainMenuAction.performFind, keyEquivalent: "f")
        menu.addItem(withTitle: "Go to Line", action: MacMainMenuAction.performGoToLine, keyEquivalent: "l")
        menu.addItem(.separator())

        let foldAll = menu.addItem(withTitle: "Fold All", action: MacMainMenuAction.performFoldAll, keyEquivalent: "k")
        foldAll.keyEquivalentModifierMask = [.command, .shift]

        let unfoldAll = menu.addItem(withTitle: "Unfold All", action: MacMainMenuAction.performUnfoldAll, keyEquivalent: "u")
        unfoldAll.keyEquivalentModifierMask = [.command, .shift]

        item.submenu = menu
        return item
    }
}
#endif

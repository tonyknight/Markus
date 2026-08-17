import Foundation
#if os(macOS)
import AppKit
#endif
import Testing
@testable import Markus

#if os(macOS)
@MainActor
struct MacMainMenuTests {
    @Test func mainMenuContainsFileAndEditTopLevelItems() {
        let menu = MacMainMenu.build()
        let titles = menu.items.map(\.title)
        #expect(titles.contains("File"))
        #expect(titles.contains("Edit"))
    }

    @Test func fileMenuHasNewOpenOpenFolderOpenRecentAndSaveWithStandardShortcuts() throws {
        let menu = MacMainMenu.build()
        let fileItem = try #require(menu.items.first { $0.title == "File" })
        let file = try #require(fileItem.submenu)
        let titles = file.items.map(\.title)
        #expect(titles.contains("New"))
        #expect(titles.contains("Open\u{2026}"))
        #expect(titles.contains("Open Folder\u{2026}"))
        #expect(titles.contains("Open Recent"))
        #expect(titles.contains("Save"))

        let newItem = try #require(file.items.first { $0.title == "New" })
        #expect(newItem.action == #selector(NSDocumentController.newDocument(_:)))
        #expect(newItem.keyEquivalent == "n")
        #expect(newItem.keyEquivalentModifierMask == [.command])
        #expect(newItem.target == nil)

        let openItem = try #require(file.items.first { $0.title == "Open\u{2026}" })
        #expect(openItem.action == #selector(NSDocumentController.openDocument(_:)))
        #expect(openItem.keyEquivalent == "o")
        #expect(openItem.keyEquivalentModifierMask == [.command])
        #expect(openItem.target == nil)

        let openFolderItem = try #require(file.items.first { $0.title == "Open Folder\u{2026}" })
        #expect(openFolderItem.keyEquivalent == "o")
        #expect(openFolderItem.keyEquivalentModifierMask == [.command, .shift])
        #expect(openFolderItem.target == nil)
        #expect(openFolderItem.action != nil)

        let openRecentItem = try #require(file.items.first { $0.title == "Open Recent" })
        #expect(openRecentItem.submenu != nil)

        let saveItem = try #require(file.items.first { $0.title == "Save" })
        #expect(saveItem.action == #selector(NSDocument.save(_:)))
        #expect(saveItem.keyEquivalent == "s")
        #expect(saveItem.keyEquivalentModifierMask == [.command])
        #expect(saveItem.target == nil)
    }

    @Test func editMenuHasFindGoToLineFoldAllUnfoldAllTargetingNilWithShortcuts() throws {
        let menu = MacMainMenu.build()
        let editItem = try #require(menu.items.first { $0.title == "Edit" })
        let edit = try #require(editItem.submenu)

        for title in ["Find", "Go to Line", "Fold All", "Unfold All"] {
            let item = try #require(edit.items.first { $0.title == title })
            #expect(item.target == nil, "\(title) should target nil so it resolves via the responder chain")
            #expect(item.action != nil, "\(title) needs an action selector")
            #expect(!item.keyEquivalent.isEmpty, "\(title) needs a keyboard shortcut")
        }

        let find = try #require(edit.items.first { $0.title == "Find" })
        #expect(find.keyEquivalent == "f")
        #expect(find.keyEquivalentModifierMask == [.command])

        let goToLine = try #require(edit.items.first { $0.title == "Go to Line" })
        #expect(goToLine.keyEquivalent == "l")
        #expect(goToLine.keyEquivalentModifierMask == [.command])

        let foldAll = try #require(edit.items.first { $0.title == "Fold All" })
        #expect(foldAll.keyEquivalent == "k")
        #expect(foldAll.keyEquivalentModifierMask == [.command, .shift])

        let unfoldAll = try #require(edit.items.first { $0.title == "Unfold All" })
        #expect(unfoldAll.keyEquivalent == "u")
        #expect(unfoldAll.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test func markusAppDelegateInstallsTheBuiltMenuAsTheAppMainMenu() {
        let delegate = MarkusAppDelegate()
        NSApp.mainMenu = nil
        delegate.applicationWillFinishLaunching(Notification(name: Notification.Name("test.willFinishLaunching")))

        let installed = NSApp.mainMenu
        #expect(installed != nil)
        let titles = installed?.items.map(\.title) ?? []
        #expect(titles.contains("File"))
        #expect(titles.contains("Edit"))
    }

    // Walks the real responder chain starting at `responder` (not via
    // `NSApplication`/system key-window resolution, which is arbitrated
    // machine-wide and flaky whenever another process on the same
    // desktop also owns a window — e.g. sibling test runs). This proves
    // the same mechanism AppKit's nil-targeted action dispatch relies on
    // (`nextResponder` chain walking) without that external dependency.
    private func resolveAndPerform(_ action: Selector, startingAt responder: NSResponder) -> Bool {
        var current: NSResponder? = responder
        while let candidate = current {
            if candidate.responds(to: action) {
                _ = candidate.perform(action, with: nil)
                return true
            }
            current = candidate.nextResponder
        }
        return false
    }

    @Test func windowContentViewControllerIsSplicedIntoTheResponderChain() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)
        let viewController = try #require(window.contentViewController as? MarkdownDocumentViewController)

        // AppKit automatically inserts a window's contentViewController
        // into the responder chain between the content view and the
        // window itself; that's what lets nil-targeted Edit/Open-Folder
        // menu items resolve here.
        #expect(viewController.nextResponder === window)
    }

    @Test func customEditAndOpenFolderActionsResolveThroughTheResponderChainToTheDocument() throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)
        let viewController = try #require(window.contentViewController as? MarkdownDocumentViewController)

        #expect(!document.host.isFindPresented)
        #expect(resolveAndPerform(MacMainMenuAction.performFind, startingAt: viewController))
        #expect(document.host.isFindPresented)

        #expect(!document.host.isGoToLinePresented)
        #expect(resolveAndPerform(MacMainMenuAction.performGoToLine, startingAt: viewController))
        #expect(document.host.isGoToLinePresented)

        #expect(!document.host.isFolderImporterPresented)
        #expect(resolveAndPerform(MacMainMenuAction.performOpenFolder, startingAt: viewController))
        #expect(document.host.isFolderImporterPresented)
    }

    @Test func foldAllAndUnfoldAllTargetNilAndResolveWithoutCrashingAheadOfTheFoldService() throws {
        // Per the ticket: Fold All / Unfold All are wired to the responder
        // chain only in this ticket. The fold service itself lands in a
        // later ticket, so this only proves the action resolves and runs
        // safely, not that folding happens.
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = try #require(document.windowControllers.first?.window)
        let viewController = try #require(window.contentViewController as? MarkdownDocumentViewController)

        #expect(resolveAndPerform(MacMainMenuAction.performFoldAll, startingAt: viewController))
        #expect(resolveAndPerform(MacMainMenuAction.performUnfoldAll, startingAt: viewController))
    }

    @Test func standardDocumentActionsAreImplementedByNSDocumentControllerAndNSDocumentWithoutCustomWiring() {
        // New/Open/Save use AppKit's own document-architecture action
        // methods (menu items built with target `nil`, per MacMainMenu);
        // confirm the objects that automatic nil-targeted dispatch would
        // reach actually implement them, rather than depending on which
        // window the OS currently treats as key/main (arbitrated
        // machine-wide, and flaky under concurrent processes).
        #expect(NSDocumentController.shared.responds(to: #selector(NSDocumentController.newDocument(_:))))
        #expect(NSDocumentController.shared.responds(to: #selector(NSDocumentController.openDocument(_:))))

        let document = MarkdownDocument()
        #expect(document.responds(to: #selector(NSDocument.save(_:))))
    }

    @Test func recentDocumentItemsAreBuiltFromTheGivenURLsWithClearMenuAtTheEnd() throws {
        let first = URL(fileURLWithPath: "/tmp/markus-recent-a.md")
        let second = URL(fileURLWithPath: "/tmp/markus-recent-b.md")

        let items = MacMainMenu.recentDocumentItems(for: [first, second])
        #expect(items.count == 4) // 2 documents + separator + Clear Menu
        #expect(items[0].title == "markus-recent-a.md")
        #expect(items[0].representedObject as? URL == first)
        #expect(items[1].title == "markus-recent-b.md")
        #expect(items[1].representedObject as? URL == second)
        #expect(items[2].isSeparatorItem)
        #expect(items[3].title == "Clear Menu")
        #expect(items[3].action == #selector(NSDocumentController.clearRecentDocuments(_:)))

        let empty = MacMainMenu.recentDocumentItems(for: [])
        #expect(empty.count == 1)
        #expect(empty[0].title == "No Recent Documents")
        #expect(!empty[0].isEnabled)
    }

    @Test func openRecentSubmenuDelegateReadsFromNSDocumentController() throws {
        let menu = MacMainMenu.build()
        let fileItem = try #require(menu.items.first { $0.title == "File" })
        let file = try #require(fileItem.submenu)
        let openRecent = try #require(file.items.first { $0.title == "Open Recent" })
        let submenu = try #require(openRecent.submenu)
        #expect(submenu.delegate != nil)
    }
}
#endif

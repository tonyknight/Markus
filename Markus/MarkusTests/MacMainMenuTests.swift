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
}
#endif

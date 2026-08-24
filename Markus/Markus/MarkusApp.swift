//
//  MarkusApp.swift
//  Markus
//
//  Created by Tony Knight on 2026-08-15.
//

import SwiftUI

@main
struct MarkusApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MarkusAppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // A real `Window`, not `Settings`. SwiftUI's Settings scene is a
        // non-resizable panel; `windowResizability` does not give it
        // edge handles. Gear, Markus → Settings…, and ⌘, open this id.
        //
        // This is the only SwiftUI window scene, so it would otherwise
        // open at launch. `MarkusAppDelegate` closes that unsolicited
        // presentation; `isRestorable = false` stops session restore.
        Window("Settings", id: SettingsWindowChrome.windowID) {
            SettingsWindowView()
        }
        .defaultSize(width: 800, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            MarkusCommands()
        }
        #else
        WindowGroup {
            AppRootView()
        }
        #endif
    }
}

struct AppRootView: View {
    // Shares the single app-scoped `ThemeStore` across every iOS/iPadOS
    // scene so a theme change broadcasts to all of them (R9; J.27).
    @StateObject private var host = DocumentHost(
        session: DocumentSession(),
        recents: RecentDocuments(),
        themeStore: ThemeStore.shared
    )
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ContentView(host: host)
            .onAppear {
                ThemeStore.shared.noteSystemAppearance()
            }
            .onChange(of: colorScheme) { _, _ in
                ThemeStore.shared.noteSystemAppearance()
            }
    }
}

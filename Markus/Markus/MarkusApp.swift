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
        Settings {
            Text("Open a Markdown document to edit.")
        }
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

    var body: some View {
        ContentView(host: host)
    }
}

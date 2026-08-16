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
        #else
        WindowGroup {
            AppRootView()
        }
        #endif
    }
}

struct AppRootView: View {
    @StateObject private var host = DocumentHost()

    var body: some View {
        ContentView(host: host)
    }
}

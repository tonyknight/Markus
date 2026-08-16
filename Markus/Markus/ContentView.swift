//
//  ContentView.swift
//  Markus
//
//  Created by Tony Knight on 2026-08-15.
//

import SwiftUI

/// Placeholder shell. v1 defaults to Preview; Source arrives with the editor view.
struct ContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Markus", systemImage: "doc.plaintext")
        } description: {
            Text("Open a Markdown file to preview it.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}

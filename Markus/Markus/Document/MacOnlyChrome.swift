enum MacOnlyChrome {
    static var usesSwiftUITabBar: Bool { MacDocumentChrome.usesSwiftUITabBar }

    static var hasNSDocumentTabbingSurface: Bool {
        MacDocumentChrome.usesNSDocumentTabbing
    }

    static var hasMinimapInChrome: Bool {
        MacMinimapChrome.showsMinimap
    }

    static var minimapIsRequired: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

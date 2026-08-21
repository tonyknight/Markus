import Foundation

enum EditorSettings {
    static let defaultModeKey = "markus.editor.defaultMode"

    static func loadDefaultMode(from defaults: UserDefaults = .standard) -> EditorMode {
        guard let raw = defaults.string(forKey: defaultModeKey),
              let mode = EditorMode(rawValue: raw) else {
            return .preview
        }
        return mode
    }

    static func saveDefaultMode(_ mode: EditorMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultModeKey)
    }
}

import Foundation

enum KeyboardSharedPreferences {
    static let appGroupIdentifier = "group.com.shendongchun.windwhisper"
    static let schemaKey = "schema"
    static let hapticIntensityKey = "hapticIntensity"
    static let defaultHapticIntensity = 0.9
    /// Show the uncommitted code in the host text field (like the system
    /// keyboards) instead of above the keys.
    static let inlineCompositionKey = "inlineComposition"
    static let defaultInlineComposition = true

    static func normalizedHapticIntensity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHapticIntensity }
        return min(max(value, 0), 1)
    }
}

enum KeyboardSharedStorage {
    static func sharedContainerURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSharedPreferences.appGroupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "无法读取宿主 App 的共享输入数据。"
            ])
        }
        return container
    }

    static func userDataURL() throws -> URL {
        try sharedContainerURL().appendingPathComponent("User", isDirectory: true)
    }
}

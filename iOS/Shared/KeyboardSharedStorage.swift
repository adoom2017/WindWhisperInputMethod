import Foundation

enum KeyboardSharedStorage {
    static let appGroupIdentifier = "group.com.shendongchun.windwhisper"

    static func userDataURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "无法访问共享词库，请确认风语键盘已开启完全访问。"
            ])
        }
        return container.appendingPathComponent("User", isDirectory: true)
    }
}

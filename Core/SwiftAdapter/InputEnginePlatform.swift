import Foundation

/// Platform-neutral values used by the shared input engine.
enum InputEnginePlatform {
    static let persistentDataIdentifier = "com.shendongchun.inputmethod.windwhisper"
}

enum InputEngineModifierMask {
    static let shift: Int32 = 1 << 0
    static let control: Int32 = 1 << 2
    static let option: Int32 = 1 << 3
    static let release: Int32 = 1 << 30
}

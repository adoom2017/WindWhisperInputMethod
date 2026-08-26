import Foundation

enum InputSourceMetadata {
    static let productName = "windwhisper"
    static let bundleIdentifier = "com.shendongchun.inputmethod.windwhisper.local"
    static let persistentDataIdentifier = bundleIdentifier
    static let connectionNameKey = "InputMethodConnectionName"
    static let inputModeIdentifier = "\(bundleIdentifier).Hans"
    static let legacyPersistentDataIdentifiers = [
        "com.shendongchun.inputmethod.rime.dev"
    ]
    static let legacyInputModeIdentifiers = [
        "com.shendongchun.inputmethod.fengyu.local.Hans",
        "com.shendongchun.inputmethod.fengyu.local",
        "com.shendongchun.inputmethod.rime.dev.Hans",
        "com.shendongchun.inputmethod.rime.dev",
        "com.shendongchun.inputmethod.fengyu.Hans",
        "com.shendongchun.inputmethod.fengyu",
        "com.shendongchun.inputmethod.rime.dev.FengYuHans",
    ]
}

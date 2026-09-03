import Foundation

enum FengYuSchema: String, CaseIterable, Sendable {
    case flypy = "flypyShape"
    case flypyPhonetic = "flypyPhonetic"
    case fullPinyin = "fullPinyin"

    var displayName: String {
        switch self {
        case .flypy: "小鹤音形"
        case .flypyPhonetic: "小鹤双拼"
        case .fullPinyin: "风语全拼"
        }
    }
}

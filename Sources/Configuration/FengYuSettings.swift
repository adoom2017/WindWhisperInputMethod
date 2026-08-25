import Foundation

enum FengYuSchema: String, CaseIterable, Sendable {
    case flypy = "flypy"
    case flypyPhonetic = "double_pinyin_flypy"
    case fullPinyin = "luna_pinyin"
    case natural = "double_pinyin"
    case microsoft = "double_pinyin_mspy"
    case abc = "double_pinyin_abc"
    case cangjie = "cangjie5"

    var displayName: String {
        switch self {
        case .flypy: "小鹤双拼（音形辅码）"
        case .flypyPhonetic: "小鹤双拼（纯音码）"
        case .fullPinyin: "风语全拼"
        case .natural: "自然码双拼"
        case .microsoft: "微软双拼"
        case .abc: "智能 ABC 双拼"
        case .cangjie: "仓颉五代"
        }
    }
}

enum CandidateOrientation: String, CaseIterable, Sendable {
    case horizontal
    case vertical

    var displayName: String {
        switch self {
        case .horizontal: "横排"
        case .vertical: "竖排"
        }
    }
}

enum CandidateColorScheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

struct FengYuSettingsSnapshot: Equatable, Sendable {
    var schema: FengYuSchema
    var usesFullWidth: Bool
    var usesSimplifiedChinese: Bool
    var candidateOrientation: CandidateOrientation
    var colorScheme: CandidateColorScheme

    static let defaults = FengYuSettingsSnapshot(
        schema: .flypy,
        usesFullWidth: false,
        usesSimplifiedChinese: true,
        candidateOrientation: .horizontal,
        colorScheme: .system
    )

    func apply(to session: RimeSession) throws {
        guard session.selectSchema(identifier: schema.rawValue) else {
            throw RimeBridgeError.bridge(
                code: -2,
                message: "The selected input schema is unavailable: \(schema.rawValue)"
            )
        }
        let optionsApplied = [
            session.setOption("full_shape", enabled: usesFullWidth),
            session.setOption("simplification", enabled: usesSimplifiedChinese),
            session.setOption("zh_trad", enabled: !usesSimplifiedChinese),
            session.setOption("zh_simp", enabled: usesSimplifiedChinese),
        ].allSatisfy { $0 }
        guard optionsApplied else {
            throw RimeBridgeError.bridge(
                code: -3,
                message: "librime runtime options are unavailable."
            )
        }
    }
}

extension Notification.Name {
    static let fengYuSettingsDidChange = Notification.Name("FengYuSettingsDidChange")
    static let fengYuWillRedeploy = Notification.Name("FengYuWillRedeploy")
    static let fengYuDidRedeploy = Notification.Name("FengYuDidRedeploy")
}

final class FengYuSettingsStore: @unchecked Sendable {
    static let shared = FengYuSettingsStore()

    private enum Key {
        // v2 intentionally resets the former pure-phonetic Flypy default to
        // the user-requested 小鹤音形 schema while keeping both menu choices.
        static let schema = "settings.schema.v2"
        static let legacySchema = "settings.schema.v1"
        static let fullWidth = "settings.fullWidth.v1"
        static let simplified = "settings.simplified.v1"
        static let orientation = "settings.candidateOrientation.v1"
        static let colorScheme = "settings.colorScheme.v1"
    }

    private let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var snapshot: FengYuSettingsSnapshot {
        lock.fengYuWithLock {
            FengYuSettingsSnapshot(
                schema: enumValue(FengYuSchema.self, forKey: Key.schema)
                    ?? FengYuSettingsSnapshot.defaults.schema,
                usesFullWidth: boolValue(forKey: Key.fullWidth)
                    ?? FengYuSettingsSnapshot.defaults.usesFullWidth,
                usesSimplifiedChinese: boolValue(forKey: Key.simplified)
                    ?? FengYuSettingsSnapshot.defaults.usesSimplifiedChinese,
                candidateOrientation: enumValue(CandidateOrientation.self, forKey: Key.orientation)
                    ?? FengYuSettingsSnapshot.defaults.candidateOrientation,
                colorScheme: enumValue(CandidateColorScheme.self, forKey: Key.colorScheme)
                    ?? FengYuSettingsSnapshot.defaults.colorScheme
            )
        }
    }

    func update(_ transform: (inout FengYuSettingsSnapshot) -> Void) {
        let changed = lock.fengYuWithLock {
            let oldValue = unlockedSnapshot()
            var newValue = oldValue
            transform(&newValue)
            guard newValue != oldValue else {
                return false
            }
            write(newValue)
            return true
        }
        if changed {
            NotificationCenter.default.post(name: .fengYuSettingsDidChange, object: self)
        }
    }

    func reset() {
        let changed = lock.fengYuWithLock {
            let wasDefault = unlockedSnapshot() == .defaults
            [
                Key.schema,
                Key.legacySchema,
                Key.fullWidth,
                Key.simplified,
                Key.orientation,
                Key.colorScheme,
            ]
                .forEach(defaults.removeObject(forKey:))
            return !wasDefault
        }
        if changed {
            NotificationCenter.default.post(name: .fengYuSettingsDidChange, object: self)
        }
    }

    private func unlockedSnapshot() -> FengYuSettingsSnapshot {
        FengYuSettingsSnapshot(
            schema: enumValue(FengYuSchema.self, forKey: Key.schema)
                ?? FengYuSettingsSnapshot.defaults.schema,
            usesFullWidth: boolValue(forKey: Key.fullWidth)
                ?? FengYuSettingsSnapshot.defaults.usesFullWidth,
            usesSimplifiedChinese: boolValue(forKey: Key.simplified)
                ?? FengYuSettingsSnapshot.defaults.usesSimplifiedChinese,
            candidateOrientation: enumValue(CandidateOrientation.self, forKey: Key.orientation)
                ?? FengYuSettingsSnapshot.defaults.candidateOrientation,
            colorScheme: enumValue(CandidateColorScheme.self, forKey: Key.colorScheme)
                ?? FengYuSettingsSnapshot.defaults.colorScheme
        )
    }

    private func write(_ snapshot: FengYuSettingsSnapshot) {
        defaults.set(snapshot.schema.rawValue, forKey: Key.schema)
        defaults.set(snapshot.usesFullWidth, forKey: Key.fullWidth)
        defaults.set(snapshot.usesSimplifiedChinese, forKey: Key.simplified)
        defaults.set(snapshot.candidateOrientation.rawValue, forKey: Key.orientation)
        defaults.set(snapshot.colorScheme.rawValue, forKey: Key.colorScheme)
    }

    private func enumValue<Value: RawRepresentable>(
        _ type: Value.Type,
        forKey key: String
    ) -> Value?
    where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }

    private func boolValue(forKey key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.bool(forKey: key)
    }
}

private extension NSLock {
    func fengYuWithLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}

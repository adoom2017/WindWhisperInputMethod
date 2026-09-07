import SwiftUI

private enum KeyboardPreferences {
    static let schemaKey = "schema"
    static let appGroupIdentifier = "group.com.shendongchun.windwhisper"
}

@main
struct WindWhisperApp: App {
    init() {
        let sharedDefaults = UserDefaults(suiteName: KeyboardPreferences.appGroupIdentifier)
            ?? .standard
        if sharedDefaults.object(forKey: KeyboardPreferences.schemaKey) == nil,
           let legacySchema = UserDefaults.standard.string(forKey: KeyboardPreferences.schemaKey) {
            sharedDefaults.set(legacySchema, forKey: KeyboardPreferences.schemaKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(
        KeyboardPreferences.schemaKey,
        store: UserDefaults(suiteName: KeyboardPreferences.appGroupIdentifier)
    )
    private var schema = "flypyShape"

    var body: some View {
        NavigationStack {
            Form {
                Section("输入方案") {
                    Picker("方案", selection: $schema) {
                        Text("小鹤音形").tag("flypyShape")
                        Text("小鹤双拼").tag("flypyPhonetic")
                        Text("风语全拼").tag("fullPinyin")
                    }
                }

                Section {
                    NavigationLink("自定义词组") {
                        CustomPhrasesView()
                    }
                } footer: {
                    Text("自定义词组仅在小鹤音形方案下生效。")
                }

                Section {
                    Label(
                        "请前往“设置 → 通用 → 键盘 → 键盘 → 风语”开启完全访问。",
                        systemImage: "gear"
                    )
                        .foregroundStyle(.secondary)
                } header: {
                    Text("设置风语键盘")
                }

                Section("隐私") {
                    Label("所有输入和词库查询均在设备本地完成", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("风语输入法")
        }
    }
}

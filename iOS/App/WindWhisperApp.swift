import SwiftUI

private enum KeyboardPreferences {
    static let schemaKey = KeyboardSharedPreferences.schemaKey
    static let appGroupIdentifier = KeyboardSharedPreferences.appGroupIdentifier
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

    @AppStorage(
        KeyboardSharedPreferences.hapticIntensityKey,
        store: UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier)
    )
    private var hapticIntensity = KeyboardSharedPreferences.defaultHapticIntensity

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
                        "建议前往“设置 → 通用 → 键盘 → 风语”开启“允许完全访问”。",
                        systemImage: "gear"
                    )
                        .foregroundStyle(.secondary)
                } header: {
                    Text("设置风语键盘")
                } footer: {
                    Text("开启后可获得按键震动等完整的第三方键盘系统能力。不开启时仍可正常输入、显示候选并读取宿主配置。")
                }

                Section("按键反馈") {
                    HStack {
                        Text("震动强度")
                        Spacer()
                        Text("\(Int(hapticIntensity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $hapticIntensity, in: 0...1, step: 0.05)
                        .accessibilityLabel("震动强度")
                        .accessibilityValue("\(Int(hapticIntensity * 100))%")
                    Text("设为 0% 可关闭按键震动。关闭“允许完全访问”时，系统可能不提供第三方键盘的震动反馈。")
                        .foregroundStyle(.secondary)
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

import SwiftUI

@main
struct WindWhisperApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("schema", store: UserDefaults(suiteName: "group.com.shendongchun.windwhisper"))
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
                    Text("请在 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 中启用“风语”。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("风语输入法")
        }
    }
}

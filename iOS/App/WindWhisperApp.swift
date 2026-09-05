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
    @AppStorage("schema")
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
                    Text("请在 设置 → 通用 → 键盘 → 键盘 中添加“风语”，并开启“允许完全访问”以使用按键触感反馈。风语仍在设备上离线处理输入。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("风语输入法")
        }
    }
}

import SwiftUI

@main
struct WindWhisperApp: App {
    init() {
        let sharedDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier)
            ?? .standard
        if sharedDefaults.object(forKey: KeyboardSharedPreferences.schemaKey) == nil,
           let legacySchema = UserDefaults.standard.string(forKey: KeyboardSharedPreferences.schemaKey) {
            sharedDefaults.set(legacySchema, forKey: KeyboardSharedPreferences.schemaKey)
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
        KeyboardSharedPreferences.schemaKey,
        store: UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier)
    )
    private var schema = "flypyShape"

    @AppStorage(
        KeyboardSharedPreferences.hapticIntensityKey,
        store: UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier)
    )
    private var hapticIntensity = KeyboardSharedPreferences.defaultHapticIntensity

    @AppStorage(
        KeyboardSharedPreferences.inlineCompositionKey,
        store: UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier)
    )
    private var inlineComposition = KeyboardSharedPreferences.defaultInlineComposition

    @Environment(\.openURL) private var openURL
    @State private var trialText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandHeader()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    SetupStep(number: 1, text: "打开“设置 → 通用 → 键盘 → 键盘”，点“添加新键盘”，选择“风语”。")
                    SetupStep(number: 2, text: "在键盘列表中点“风语”，开启“允许完全访问”，以获得按键震动。")
                    SetupStep(number: 3, text: "输入时长按或轻点地球键，切换到风语。")
                    Button("打开设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                } header: {
                    Text("开始使用")
                } footer: {
                    Text("不开启“允许完全访问”也能正常输入和选词，只是系统可能不提供按键震动。")
                }

                Section("试一试") {
                    TextField("切换到风语后在这里输入", text: $trialText, axis: .vertical)
                        .lineLimit(1...4)
                }

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
                    Toggle("在输入框中显示编码", isOn: $inlineComposition)
                } header: {
                    Text("编码显示")
                } footer: {
                    Text("开启时，输入的编码像系统键盘一样显示在输入框里；关闭后显示在候选栏左侧。个别 App 中编码显示异常时，可以关闭此项。")
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
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Brand.accent)
    }
}

/// Brand colors from docs/DESIGN_SYSTEM.md.
enum Brand {
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x86 / 255, green: 0xB6 / 255, blue: 0xCF / 255, alpha: 1)
            : UIColor(red: 0x2F / 255, green: 0x6B / 255, blue: 0x8A / 255, alpha: 1)
    })
    /// The icon tile stays the light-mode accent in both appearances, like the app icon.
    static let tile = Color(red: 0x2F / 255, green: 0x6B / 255, blue: 0x8A / 255)
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wind")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Brand.tile, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("风语输入法")
                    .font(.title2.weight(.semibold))
                Text("小鹤音形 · 小鹤双拼 · 全拼，全部在本机完成")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Brand.accent)
                .frame(width: 16)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

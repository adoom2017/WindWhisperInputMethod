@preconcurrency import AppKit

enum FengYuDiagnostics {
    static func render(
        settings: FengYuSettingsSnapshot,
        runtime: NativeRuntimeDiagnosticStatus,
        bundle: Bundle = .main
    ) -> String {
        let bundleIdentifier = bundle.bundleIdentifier ?? InputSourceMetadata.bundleIdentifier
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        return """
        风语脱敏诊断
        productVersion=\(version)
        bundleIdentifier=\(bundleIdentifier)
        executableArchitecture=\(executableArchitecture)
        macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)
        engineReady=\(runtime.isReady)
        engineVersion=\(runtime.version)
        selectedSchema=\(settings.schema.rawValue)
        fullWidth=\(settings.usesFullWidth)
        simplifiedChinese=\(settings.usesSimplifiedChinese)
        candidateOrientation=\(settings.candidateOrientation.rawValue)
        colorScheme=\(settings.colorScheme.rawValue)
        userDataDirectory=\(runtime.userDataDirectoryExists ? "present" : "missing")
        logDirectory=\(runtime.logDirectoryExists ? "present" : "missing")
        startupErrorPresent=\(runtime.lastError != nil)
        inputContentIncluded=false
        """
    }

    private static var executableArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}

final class FengYuSettingsMenuController: NSObject, NSMenuDelegate, @unchecked Sendable {
    static let shared = FengYuSettingsMenuController()

    let menu = NSMenu(title: "风语")
    private let store: FengYuSettingsStore
    private var isApplyingCustomWords = false
    private var customWordsEditor: CustomWordsEditorWindowController?

    init(store: FengYuSettingsStore = .shared) {
        self.store = store
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        let settings = store.snapshot
        menu.removeAllItems()

        let status = NSMenuItem(title: "当前：\(settings.schema.displayName)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        addSelectionGroup(
            title: "输入方案",
            values: FengYuSchema.allCases,
            selected: settings.schema,
            title: \.displayName,
            action: schemaAction(for:)
        )

        menu.addItem(.separator())

        let fullWidth = actionItem(
            title: "全角字符",
            action: #selector(WindWhisperInputController.fengYuToggleFullWidthCommand(_:)),
            state: settings.usesFullWidth
        )
        menu.addItem(fullWidth)

        let simplified = actionItem(
            title: "简体中文",
            action: #selector(WindWhisperInputController.fengYuToggleSimplifiedChineseCommand(_:)),
            state: settings.usesSimplifiedChinese
        )
        menu.addItem(simplified)

        menu.addItem(.separator())
        addSelectionGroup(
            title: "候选排列",
            values: CandidateOrientation.allCases,
            selected: settings.candidateOrientation,
            title: \.displayName,
            action: orientationAction(for:)
        )

        menu.addItem(.separator())
        addSelectionGroup(
            title: "候选主题",
            values: CandidateColorScheme.allCases,
            selected: settings.colorScheme,
            title: \.displayName,
            action: colorSchemeAction(for:)
        )

        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: "管理自定义词…",
            action: #selector(WindWhisperInputController.fengYuManageCustomWordsCommand(_:))
        ))
        menu.addItem(actionItem(
            title: "打开用户目录",
            action: #selector(WindWhisperInputController.fengYuOpenUserDirectoryCommand(_:))
        ))
        menu.addItem(actionItem(
            title: "查看脱敏诊断…",
            action: #selector(WindWhisperInputController.fengYuShowDiagnosticsCommand(_:))
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: "恢复默认设置…",
            action: #selector(WindWhisperInputController.fengYuResetSettingsCommand(_:))
        ))
    }

    private func actionItem(
        title: String,
        action: Selector,
        state: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        // InputMethodKit routes command menu selectors through the active
        // IMKInputController and passes a command dictionary as the sender.
        item.target = nil
        item.state = state ? .on : .off
        return item
    }

    private func addSelectionGroup<Value: Equatable>(
        title: String,
        values: [Value],
        selected: Value,
        title titleKeyPath: KeyPath<Value, String>,
        action: (Value) -> Selector
    ) {
        let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        for value in values {
            let item = actionItem(title: value[keyPath: titleKeyPath], action: action(value))
            item.indentationLevel = 1
            item.state = value == selected ? .on : .off
            menu.addItem(item)
        }
    }

    private func schemaAction(for schema: FengYuSchema) -> Selector {
        switch schema {
        case .flypy: #selector(WindWhisperInputController.fengYuSelectFlypySchemaCommand(_:))
        case .flypyPhonetic: #selector(WindWhisperInputController.fengYuSelectFlypyPhoneticSchemaCommand(_:))
        case .fullPinyin: #selector(WindWhisperInputController.fengYuSelectFullPinyinSchemaCommand(_:))
        }
    }

    private func orientationAction(for orientation: CandidateOrientation) -> Selector {
        switch orientation {
        case .horizontal: #selector(WindWhisperInputController.fengYuSelectHorizontalOrientationCommand(_:))
        case .vertical: #selector(WindWhisperInputController.fengYuSelectVerticalOrientationCommand(_:))
        }
    }

    private func colorSchemeAction(for colorScheme: CandidateColorScheme) -> Selector {
        switch colorScheme {
        case .system: #selector(WindWhisperInputController.fengYuSelectSystemColorSchemeCommand(_:))
        case .light: #selector(WindWhisperInputController.fengYuSelectLightColorSchemeCommand(_:))
        case .dark: #selector(WindWhisperInputController.fengYuSelectDarkColorSchemeCommand(_:))
        }
    }

    func selectSchema(_ schema: FengYuSchema) {
        store.update { $0.schema = schema }
        rebuildMenu()
    }

    func toggleFullWidth() {
        store.update { $0.usesFullWidth.toggle() }
        rebuildMenu()
    }

    func toggleSimplifiedChinese() {
        store.update { $0.usesSimplifiedChinese.toggle() }
        rebuildMenu()
    }

    func selectOrientation(_ orientation: CandidateOrientation) {
        store.update { $0.candidateOrientation = orientation }
        rebuildMenu()
    }

    func selectColorScheme(_ colorScheme: CandidateColorScheme) {
        store.update { $0.colorScheme = colorScheme }
        rebuildMenu()
    }

    private func applyCustomWords() {
        guard !isApplyingCustomWords else {
            return
        }
        isApplyingCustomWords = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let errorMessage: String?
            do {
                try NativeRuntime.shared.refreshConfiguration()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            DispatchQueue.main.async {
                self?.finishApplyingCustomWords(errorMessage: errorMessage)
            }
        }
    }

    func manageCustomWords() {
        DispatchQueue.main.async { [weak self] in
            self?.presentCustomWordsEditor()
        }
    }

    @MainActor
    private func presentCustomWordsEditor() {
        if let customWordsEditor, customWordsEditor.window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            customWordsEditor.window?.makeKeyAndOrderFront(nil)
            return
        }

        do {
            let store = try CustomWordsStore.applicationDefaults()
            let document = try store.load()
            let editor = CustomWordsEditorWindowController(
                document: document,
                store: store
            ) { [weak self] in
                self?.applyCustomWords()
            }
            editor.onWindowClosed = { [weak self, weak editor] in
                guard self?.customWordsEditor === editor else { return }
                self?.customWordsEditor = nil
            }
            customWordsEditor = editor
            NSApp.activate(ignoringOtherApps: true)
            editor.showWindow(nil)
            editor.window?.makeKeyAndOrderFront(nil)
        } catch {
            showMessage(
                title: "无法读取自定义词",
                message: "请检查 custom_words.tsv 的格式后重试。\n\n\(error.localizedDescription)",
                style: .warning
            )
        }
    }

    private func finishApplyingCustomWords(errorMessage: String?) {
        isApplyingCustomWords = false
        if let errorMessage {
            showMessage(
                title: "自定义词已保存，但未能应用",
                message: "请检查自定义词内容后重新保存。\n\n\(errorMessage)",
                style: .warning
            )
        } else {
            NotificationCenter.default.post(name: .fengYuWillRefreshConfiguration, object: self)
            NotificationCenter.default.post(name: .fengYuDidRefreshConfiguration, object: self)
            showMessage(title: "保存完成", message: "自定义词已经生效。")
        }
    }

    func openUserDirectory() {
        do {
            let url = try InputServicePaths.applicationDefaults().userData
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(url) else {
                showMessage(
                    title: "无法打开用户目录",
                    message: "Finder 没有接受打开目录的请求。请稍后重试。",
                    style: .warning
                )
                return
            }
        } catch {
            showMessage(
                title: "无法打开用户目录",
                message: "请确认当前用户目录可写。\n\n\(error.localizedDescription)",
                style: .warning
            )
        }
    }

    func showDiagnostics() {
        let text = FengYuDiagnostics.render(
            settings: store.snapshot,
            runtime: NativeRuntime.shared.diagnosticStatus()
        )
        let alert = NSAlert()
        alert.messageText = "风语脱敏诊断"
        alert.informativeText = "诊断不包含已输入文字、候选内容或完整用户路径。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "复制")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func resetSettings() {
        let alert = NSAlert()
        alert.messageText = "恢复风语默认设置？"
        alert.informativeText = "将恢复小鹤双拼、半角、简体、横排和跟随系统主题。用户词典与 .custom.yaml 文件不会被删除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        store.reset()
        rebuildMenu()
    }

    private func showMessage(
        title: String,
        message: String,
        style: NSAlert.Style = .informational
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

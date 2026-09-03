import UIKit
import OSLog

private actor KeyboardInputRuntime {
    static let shared = KeyboardInputRuntime()

    private var service: InputService?
    private var loadedSchema: FengYuSchema?

    func makeSession(
        paths: InputServicePaths,
        schema: FengYuSchema
    ) throws -> (service: InputService, session: InputSession) {
        let service: InputService
        if let cachedService = self.service, loadedSchema == schema {
            service = cachedService
        } else {
            let loadedService = try InputService(paths: paths, enabledSchemas: [schema])
            self.service = loadedService
            loadedSchema = schema
            service = loadedService
        }
        return (service, try service.makeSession())
    }
}

final class KeyboardViewController: UIInputViewController {
    private enum LayoutMode {
        case letters
        case numbers
        case symbols
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 6
        static let suggestionToKeysSpacing: CGFloat = 7
        static let keyRowSpacing: CGFloat = 10.5
        static let keySpacing: CGFloat = 6
        static let keyHeight: CGFloat = 43
        static let utilityKeyHeight: CGFloat = 43
        static let suggestionHeight: CGFloat = 24
        static let keyCornerRadius: CGFloat = 8
        static let contentHeight: CGFloat = 239
        static let suggestionVerticalOffset: CGFloat = 2
    }

    private let logger = Logger(
        subsystem: "com.shendongchun.inputmethod.windwhisper.ios.keyboard",
        category: "Keyboard"
    )
    private let groupID = "group.com.shendongchun.windwhisper"

    private var session: InputSession?
    private var service: InputService?
    private var startupErrorDescription: String?
    private var layoutMode = LayoutMode.letters
    private var isShifted = false
    private var startupTask: Task<Void, Never>?

    private let rootStack = UIStackView()
    private let keyboardRowsStack = UIStackView()
    private let suggestionScrollView = UIScrollView()
    private let suggestionsStack = UIStackView()
    private let compositionLabel = UILabel()
    private let shiftButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let asciiButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _) in
            controller.applyColors()
        }
        buildView()
        startEngine()
    }

    deinit {
        startupTask?.cancel()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        session?.clearComposition()
        if session != nil { compositionLabel.text = "" }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyColors()
        refresh()
    }

    private func startEngine() {
        guard let resources = Bundle.main.resourceURL else {
            showStartupError("找不到词库资源")
            return
        }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            showStartupError("无法访问共享数据")
            return
        }
        let paths = InputServicePaths(
            sharedData: resources,
            userData: container.appendingPathComponent("User"),
            logs: container.appendingPathComponent("Logs")
        )
        let schemaIdentifier = UserDefaults(suiteName: groupID)?.string(forKey: "schema") ?? "flypyShape"
        let schema = FengYuSchema(rawValue: schemaIdentifier) ?? .flypy
        showStatus("正在加载")
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            do {
                let result = try await KeyboardInputRuntime.shared.makeSession(paths: paths, schema: schema)
                try Task.checkCancellation()
                guard let self else { return }
                _ = result.session.selectSchema(identifier: schema.rawValue)
                service = result.service
                session = result.session
                startupErrorDescription = nil
                logger.notice("WindWhisper input engine is ready")
                refresh()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.showStartupError(error.localizedDescription)
            }
        }
    }

    private func showStartupError(_ description: String) {
        startupErrorDescription = description
        showStatus("引擎不可用")
        logger.error("Input engine startup failed: \(description, privacy: .public)")
    }

    private func buildView() {
        view.backgroundColor = .clear

        rootStack.axis = .vertical
        rootStack.spacing = Metrics.suggestionToKeysSpacing
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        configureSuggestionBar()
        configureKeyboardRows()
        rootStack.addArrangedSubview(suggestionScrollView)
        rootStack.addArrangedSubview(keyboardRowsStack)

        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.horizontalInset),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.horizontalInset),
            rootStack.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 5),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            rootStack.heightAnchor.constraint(equalToConstant: Metrics.contentHeight)
        ])

        applyColors()
    }

    private func configureSuggestionBar() {
        suggestionScrollView.showsHorizontalScrollIndicator = false
        suggestionScrollView.alwaysBounceHorizontal = true
        suggestionScrollView.heightAnchor.constraint(equalToConstant: Metrics.suggestionHeight).isActive = true

        suggestionsStack.axis = .horizontal
        suggestionsStack.alignment = .fill
        suggestionsStack.spacing = 5
        suggestionsStack.translatesAutoresizingMaskIntoConstraints = false
        suggestionScrollView.addSubview(suggestionsStack)
        NSLayoutConstraint.activate([
            suggestionsStack.leadingAnchor.constraint(equalTo: suggestionScrollView.contentLayoutGuide.leadingAnchor),
            suggestionsStack.trailingAnchor.constraint(equalTo: suggestionScrollView.contentLayoutGuide.trailingAnchor),
            suggestionsStack.topAnchor.constraint(equalTo: suggestionScrollView.contentLayoutGuide.topAnchor),
            suggestionsStack.bottomAnchor.constraint(equalTo: suggestionScrollView.contentLayoutGuide.bottomAnchor),
            suggestionsStack.heightAnchor.constraint(equalTo: suggestionScrollView.frameLayoutGuide.heightAnchor)
        ])

        compositionLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        compositionLabel.textAlignment = .left
        compositionLabel.transform = CGAffineTransform(
            translationX: 0,
            y: Metrics.suggestionVerticalOffset
        )
        compositionLabel.setContentHuggingPriority(.required, for: .horizontal)
        compositionLabel.accessibilityLabel = "正在输入"
        showQuickPunctuation()
    }

    private func configureKeyboardRows() {
        keyboardRowsStack.axis = .vertical
        keyboardRowsStack.spacing = Metrics.keyRowSpacing
        rebuildCharacterRows()
    }

    private func rebuildCharacterRows() {
        keyboardRowsStack.arrangedSubviews.forEach {
            keyboardRowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows: [[String]]
        switch layoutMode {
        case .letters:
            rows = [
                Array("qwertyuiop").map(String.init),
                Array("asdfghjkl").map(String.init),
                Array("zxcvbnm").map(String.init)
            ]
        case .numbers:
            rows = [
                Array("1234567890").map(String.init),
                ["-", "/", ":", ";", "(", ")", "$", "&", "@"],
                [".", ",", "?", "!", "'", "\""]
            ]
        case .symbols:
            rows = [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "€", "£", "¥"],
                ["·", "…", "，", "。", "？", "！"]
            ]
        }

        keyboardRowsStack.addArrangedSubview(makeCharacterRow(rows[0]))
        keyboardRowsStack.addArrangedSubview(makeCharacterRow(rows[1], horizontalInset: 20))
        keyboardRowsStack.addArrangedSubview(makeThirdRow(rows[2]))
        keyboardRowsStack.addArrangedSubview(makeUtilityRow())
        applyColors()
    }

    private func makeCharacterRow(_ titles: [String], horizontalInset: CGFloat = 0) -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: Metrics.keyHeight).isActive = true
        let row = equalWidthStack()
        titles.forEach { row.addArrangedSubview(makeCharacterKey($0)) }
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeThirdRow(_ titles: [String]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Metrics.keySpacing
        row.heightAnchor.constraint(equalToConstant: Metrics.keyHeight).isActive = true

        if layoutMode == .letters {
            configureIconButton(shiftButton, symbol: isShifted ? "shift.fill" : "shift", accessibilityLabel: "大写")
            shiftButton.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
            row.addArrangedSubview(shiftButton)
        } else {
            let title = layoutMode == .numbers ? "#+=" : "123"
            row.addArrangedSubview(makeActionKey(title, accessibilityLabel: "切换符号", action: #selector(toggleSymbolPage)))
        }

        let characterStack = equalWidthStack()
        titles.forEach { characterStack.addArrangedSubview(makeCharacterKey($0)) }
        row.addArrangedSubview(characterStack)

        let backspace = makeIconKey("delete.left", accessibilityLabel: "删除", action: #selector(backspace))
        row.addArrangedSubview(backspace)
        NSLayoutConstraint.activate([
            row.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 46),
            backspace.widthAnchor.constraint(equalToConstant: 46)
        ])
        return row
    }

    private func makeUtilityRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Metrics.keySpacing
        row.heightAnchor.constraint(equalToConstant: Metrics.utilityKeyHeight).isActive = true

        let modeTitle = layoutMode == .letters ? "123" : "ABC"
        configureTextButton(modeButton, title: modeTitle, accessibilityLabel: layoutMode == .letters ? "数字键盘" : "字母键盘")
        modeButton.addTarget(self, action: #selector(toggleLayoutMode), for: .touchUpInside)
        let space = makeSpaceKey()
        let returnButton = makeIconKey("return", accessibilityLabel: "换行", action: #selector(insertNewline))

        row.addArrangedSubview(modeButton)
        row.addArrangedSubview(space)
        row.addArrangedSubview(returnButton)
        NSLayoutConstraint.activate([
            modeButton.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.24, constant: -4),
            returnButton.widthAnchor.constraint(equalTo: modeButton.widthAnchor)
        ])
        return row
    }

    private func makeSpaceKey() -> UIButton {
        let space = makeActionKey("", accessibilityLabel: "空格", action: #selector(space))
        asciiButton.removeTarget(nil, action: nil, for: .allEvents)
        asciiButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        asciiButton.accessibilityLabel = "切换中英文"
        asciiButton.addTarget(self, action: #selector(toggleASCII), for: .touchUpInside)
        asciiButton.translatesAutoresizingMaskIntoConstraints = false
        space.addSubview(asciiButton)
        NSLayoutConstraint.activate([
            asciiButton.trailingAnchor.constraint(equalTo: space.trailingAnchor, constant: -4),
            asciiButton.bottomAnchor.constraint(equalTo: space.bottomAnchor, constant: -2),
            asciiButton.widthAnchor.constraint(equalToConstant: 42),
            asciiButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        return space
    }

    private func equalWidthStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.keySpacing
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeCharacterKey(_ title: String) -> UIButton {
        let visibleTitle = isShifted && layoutMode == .letters ? title.uppercased() : title
        return makeActionKey(visibleTitle, accessibilityLabel: visibleTitle, action: #selector(keyPressed(_:)))
    }

    private func makeActionKey(_ title: String, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        configureTextButton(button, title: title, accessibilityLabel: accessibilityLabel)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeIconKey(_ symbol: String, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        configureIconButton(button, symbol: symbol, accessibilityLabel: accessibilityLabel)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func configureTextButton(_ button: UIButton, title: String, accessibilityLabel: String) {
        button.removeTarget(nil, action: nil, for: .allEvents)
        button.setTitle(title, for: .normal)
        button.setImage(nil, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: title.count > 2 ? 18 : 23, weight: .regular)
        styleKey(button)
        button.accessibilityLabel = accessibilityLabel
    }

    private func configureIconButton(_ button: UIButton, symbol: String, accessibilityLabel: String) {
        button.removeTarget(nil, action: nil, for: .allEvents)
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        button.setTitle(nil, for: .normal)
        button.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
        styleKey(button)
        button.accessibilityLabel = accessibilityLabel
    }

    private func styleKey(_ button: UIButton) {
        button.tintColor = keyForegroundColor
        button.setTitleColor(keyForegroundColor, for: .normal)
        button.backgroundColor = keyBackgroundColor
        button.layer.cornerRadius = Metrics.keyCornerRadius
        button.layer.cornerCurve = .continuous
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = textDocumentProxy.keyboardAppearance == .dark ? 0 : 0.16
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func applyColors() {
        view.backgroundColor = .clear
        compositionLabel.textColor = keyForegroundColor
        suggestionScrollView.backgroundColor = .clear
        findButtons(in: rootStack).forEach { button in
            if button === asciiButton || button.superview === suggestionsStack {
                button.tintColor = keyForegroundColor
                button.setTitleColor(keyForegroundColor, for: .normal)
                button.backgroundColor = .clear
                button.layer.shadowOpacity = 0
            } else {
                styleKey(button)
            }
        }
    }

    private func findButtons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { child -> [UIButton] in
            let current = child as? UIButton
            return (current.map { [$0] } ?? []) + findButtons(in: child)
        }
    }

    private var keyBackgroundColor: UIColor {
        textDocumentProxy.keyboardAppearance == .dark
            ? UIColor(red: 0.38, green: 0.39, blue: 0.42, alpha: 1)
            : .white
    }

    private var keyForegroundColor: UIColor {
        textDocumentProxy.keyboardAppearance == .dark ? .white : .black
    }

    private func showQuickPunctuation() {
        replaceSuggestions()
        ["，", "。", "？", "！", "、", "……"].forEach { punctuation in
            let button = UIButton(type: .system)
            button.setTitle(punctuation, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 21)
            button.setTitleColor(keyForegroundColor, for: .normal)
            button.transform = CGAffineTransform(
                translationX: 0,
                y: Metrics.suggestionVerticalOffset
            )
            button.accessibilityLabel = punctuation
            button.addAction(UIAction { [weak self] _ in
                self?.insertPunctuation(punctuation)
            }, for: .touchUpInside)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
            suggestionsStack.addArrangedSubview(button)
        }
    }

    private func showCandidates(_ candidates: [(index: Int, text: String)], composition: String) {
        replaceSuggestions()
        if !composition.isEmpty {
            compositionLabel.text = composition
            compositionLabel.accessibilityValue = composition
            suggestionsStack.addArrangedSubview(compositionLabel)
            compositionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }
        for candidate in candidates {
            let button = UIButton(type: .system)
            button.setTitle(candidate.text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 19)
            button.setTitleColor(keyForegroundColor, for: .normal)
            button.transform = CGAffineTransform(
                translationX: 0,
                y: Metrics.suggestionVerticalOffset
            )
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
            button.accessibilityLabel = "候选词 \(candidate.text)"
            button.addAction(UIAction { [weak self] _ in
                _ = self?.session?.selectCandidate(at: candidate.index)
                self?.refresh()
            }, for: .touchUpInside)
            suggestionsStack.addArrangedSubview(button)
        }
    }

    private func showStatus(_ message: String) {
        replaceSuggestions()
        let label = UILabel()
        label.text = message
        label.textColor = keyForegroundColor
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.transform = CGAffineTransform(
            translationX: 0,
            y: Metrics.suggestionVerticalOffset
        )
        suggestionsStack.addArrangedSubview(label)
    }

    private func replaceSuggestions() {
        suggestionsStack.arrangedSubviews.forEach {
            suggestionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func insertPunctuation(_ punctuation: String) {
        textDocumentProxy.insertText(punctuation)
        refresh()
    }

    @objc private func keyPressed(_ sender: UIButton) {
        guard let title = sender.currentTitle, let value = title.lowercased().first else { return }
        let output = isShifted ? String(value).uppercased() : String(value)
        guard layoutMode == .letters else {
            textDocumentProxy.insertText(output)
            refresh()
            return
        }
        let keyCode = Int32(output.utf8.first ?? 0)
        let handled = session?.process(keyCode: keyCode) ?? false
        if !handled { textDocumentProxy.insertText(output) }
        if isShifted {
            isShifted = false
            rebuildCharacterRows()
        }
        refresh()
    }

    @objc private func space() {
        let handled = session?.process(keyCode: 0x20) ?? false
        if !handled { textDocumentProxy.insertText(" ") }
        refresh()
    }

    @objc private func backspace() {
        if session?.process(keyCode: 0xFF08) != true { textDocumentProxy.deleteBackward() }
        refresh()
    }

    @objc private func insertNewline() {
        textDocumentProxy.insertText("\n")
        refresh()
    }

    @objc private func toggleASCII() {
        guard let session else { return }
        _ = session.setOption("ascii_mode", enabled: session.option("ascii_mode") != true)
        refresh()
    }

    @objc private func toggleShift() {
        isShifted.toggle()
        rebuildCharacterRows()
    }

    @objc private func toggleLayoutMode() {
        layoutMode = layoutMode == .letters ? .numbers : .letters
        isShifted = false
        rebuildCharacterRows()
    }

    @objc private func toggleSymbolPage() {
        layoutMode = layoutMode == .numbers ? .symbols : .numbers
        rebuildCharacterRows()
    }

    private func refresh() {
        guard let session else {
            showStatus(startupErrorDescription == nil ? "正在加载" : "引擎不可用")
            asciiButton.setTitle("中", for: .normal)
            return
        }
        guard let snapshot = try? session.readSnapshot() else { return }
        asciiButton.setTitle(snapshot.status.isASCIIMode ? "英" : "中", for: .normal)
        asciiButton.accessibilityValue = snapshot.status.isASCIIMode ? "英文模式" : "中文模式"

        let composition = snapshot.composition?.text ?? ""
        let candidates = snapshot.menu.candidates.enumerated().map { (index: $0.offset, text: $0.element.text) }
        if composition.isEmpty && candidates.isEmpty {
            showQuickPunctuation()
        } else {
            showCandidates(candidates, composition: composition)
        }
        if let commit = snapshot.commitText { textDocumentProxy.insertText(commit) }
    }
}

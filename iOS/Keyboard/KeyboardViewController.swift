import UIKit
import OSLog

private actor KeyboardInputRuntime {
    static let shared = KeyboardInputRuntime()

    private var service: InputService?
    private var loadedSchema: FengYuSchema?

    func makeSession(
        paths: InputServicePaths,
        schema: FengYuSchema
    ) throws -> (service: InputService, session: InputSession, reusedService: Bool) {
        let service: InputService
        let reusedService: Bool
        if let cachedService = self.service, loadedSchema == schema {
            service = cachedService
            reusedService = true
        } else {
            let loadedService = try InputService(paths: paths, enabledSchemas: [schema])
            self.service = loadedService
            loadedSchema = schema
            service = loadedService
            reusedService = false
        }
        return (service, try service.makeSession(), reusedService)
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
        static let inputViewHeight: CGFloat = contentHeight + 9
        static let suggestionVerticalOffset: CGFloat = 2
    }

    /// Gives the keyboard host a stable size before it lays out the extension's content.
    private final class SelfSizingInputView: UIInputView {
#if DEBUG
        private static let sizingLogger = Logger(
            subsystem: "com.shendongchun.inputmethod.windwhisper.ios.keyboard",
            category: "Keyboard"
        )
#endif

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: Metrics.inputViewHeight)
        }

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            let fittingWidth = size.width > 0 ? size.width : frame.width
            return CGSize(width: fittingWidth, height: Metrics.inputViewHeight)
        }

        override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
            let fittedSize = super.systemLayoutSizeFitting(targetSize)
#if DEBUG
            SelfSizingInputView.sizingLogger.notice(
                "One-argument systemLayoutSizeFitting target=\(String(describing: targetSize), privacy: .public) super=\(String(describing: fittedSize), privacy: .public) returnedHeight=\(Metrics.inputViewHeight, privacy: .public)"
            )
#endif
            return CGSize(width: fittedSize.width, height: Metrics.inputViewHeight)
        }

        override func systemLayoutSizeFitting(
            _ targetSize: CGSize,
            withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
            verticalFittingPriority: UILayoutPriority
        ) -> CGSize {
            let fittedSize = super.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: horizontalFittingPriority,
                verticalFittingPriority: verticalFittingPriority
            )
            return CGSize(width: fittedSize.width, height: Metrics.inputViewHeight)
        }

        init() {
            super.init(
                frame: CGRect(x: 0, y: 0, width: 0, height: Metrics.inputViewHeight),
                // The keyboard style asks UIKit to add the system keyboard
                // backdrop. That backdrop is hosted in a remote window and
                // can be snapshotted at its temporary full-screen height
                // during input-mode changes. The extension draws its own
                // content, so use the plain input-view path instead.
                inputViewStyle: .default
            )
            configureSelfSizing()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configureSelfSizing()
        }

        private func configureSelfSizing() {
            allowsSelfSizing = true
            setContentHuggingPriority(.required, for: .vertical)
            setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }

    /// Provides native-style immediate pressed appearance while the controller
    /// handles haptics through the button's `.touchDown` control event.
    private final class KeyboardButton: UIButton {
        private var restingTransform = CGAffineTransform.identity

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            restingTransform = transform
            let changes = {
                self.transform = self.restingTransform.scaledBy(x: 1.08, y: 1.08)
                self.layer.zPosition = 10
            }
            if UIAccessibility.isReduceMotionEnabled {
                changes()
            } else {
                UIView.animate(withDuration: 0.06, animations: changes)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            restorePressedAppearance()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            restorePressedAppearance()
        }

        private func restorePressedAppearance() {
            let changes = {
                self.transform = self.restingTransform
                self.layer.zPosition = 0
            }
            if UIAccessibility.isReduceMotionEnabled {
                changes()
            } else {
                UIView.animate(withDuration: 0.1, animations: changes)
            }
        }
    }

    private let logger = Logger(
        subsystem: "com.shendongchun.inputmethod.windwhisper.ios.keyboard",
        category: "Keyboard"
    )

    private var session: InputSession?
    private var service: InputService?
    private var startupErrorDescription: String?
    private var layoutMode = LayoutMode.letters
    private var isShifted = false
    private var startupTask: Task<Void, Never>?
    private var inputViewHeightConstraint: NSLayoutConstraint?
    private var hostPresentationVisible = false
    private var keyFeedbackGenerator: UIImpactFeedbackGenerator?
#if DEBUG
    private var layoutLogSequence = 0
    private var lastLoggedViewBounds = CGRect.null
    private var lastLoggedRootFrame = CGRect.null
#endif

    private let rootStack = UIStackView()
    private let keyboardRowsStack = UIStackView()
    private let suggestionScrollView = UIScrollView()
    private let suggestionsStack = UIStackView()
    private let compositionLabel = UILabel()
    private let shiftButton = KeyboardButton(type: .system)
    private let modeButton = KeyboardButton(type: .system)
    private let asciiButton = KeyboardButton(type: .system)

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        preferredContentSize = CGSize(width: 0, height: Metrics.inputViewHeight)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        preferredContentSize = CGSize(width: 0, height: Metrics.inputViewHeight)
    }

    override func loadView() {
        let inputView = SelfSizingInputView()
        let heightConstraint = inputView.heightAnchor.constraint(equalToConstant: Metrics.inputViewHeight)
        // The remote keyboard host owns transient presentation heights. Keeping this
        // below required lets the fixed-height content stay bottom-anchored while
        // UIKit negotiates from its temporary full-screen frame to the final height.
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        inputViewHeightConstraint = heightConstraint
        view = inputView
        self.inputView = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyFeedback()
#if DEBUG
        logger.notice(
            "Self-sizing input view allowsSelfSizing=\((self.view as? UIInputView)?.allowsSelfSizing ?? false, privacy: .public) intrinsic=\(String(describing: self.view.intrinsicContentSize), privacy: .public) initialFrame=\(String(describing: self.view.frame), privacy: .public) preferredContentSize=\(String(describing: self.preferredContentSize), privacy: .public) heightConstraintActive=\(self.inputViewHeightConstraint?.isActive ?? false, privacy: .public) heightConstraintConstant=\(self.inputViewHeightConstraint?.constant ?? -1, privacy: .public) inputView=\(String(describing: self.inputView), privacy: .public) sameView=\(self.inputView === self.view, privacy: .public)"
        )
        logLayoutState("viewDidLoad.begin")
#endif
        inputView?.allowsSelfSizing = true
        inputView?.invalidateIntrinsicContentSize()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _) in
            controller.applyColors()
        }
        buildView()
#if DEBUG
        logLayoutState("viewDidLoad.end")
#endif
        startEngine()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHostPresentationVisibility()
        updateContentVisibility()
#if DEBUG
        guard layoutLogSequence < 20,
              view.bounds != lastLoggedViewBounds || rootStack.frame != lastLoggedRootFrame else { return }
        lastLoggedViewBounds = view.bounds
        lastLoggedRootFrame = rootStack.frame
        logLayoutState("viewDidLayoutSubviews")
#endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
#if DEBUG
        logLayoutState("viewWillAppear animated=\(animated)")
#endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keyFeedbackGenerator?.prepare()
#if DEBUG
        logLayoutState("viewDidAppear animated=\(animated)")
#endif
    }

    override func viewWillDisappear(_ animated: Bool) {
#if DEBUG
        logLayoutState("viewWillDisappear animated=\(animated)")
#endif
        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
#if DEBUG
        logger.notice(
            "Layout transition target=\(String(describing: size), privacy: .public) current=\(String(describing: self.view.frame), privacy: .public)"
        )
#endif
        super.viewWillTransition(to: size, with: coordinator)
    }

#if DEBUG
    private func logLayoutState(_ phase: String) {
        layoutLogSequence += 1
        let viewOnScreen = view.convert(view.bounds, to: nil)
        let rootOnScreen = rootStack.convert(rootStack.bounds, to: nil)
        let superviewDescription = view.superview.map {
            "\(type(of: $0)) frame=\($0.frame) bounds=\($0.bounds)"
        } ?? "nil"
        var ancestorDescriptions: [String] = []
        var ancestor = view.superview
        while let current = ancestor, ancestorDescriptions.count < 6 {
            ancestorDescriptions.append(
                "\(type(of: current)){frame=\(current.frame),bg=\(String(describing: current.backgroundColor)),opaque=\(current.isOpaque),alpha=\(current.alpha),hidden=\(current.isHidden)}"
            )
            ancestor = current.superview
        }
        let ambiguityDescription: String
        if view.window != nil, !view.bounds.isEmpty {
            ambiguityDescription = String(view.hasAmbiguousLayout || rootStack.hasAmbiguousLayout)
        } else {
            ambiguityDescription = "not-checked-before-window"
        }
        logger.notice(
            "Layout #\(self.layoutLogSequence) \(phase, privacy: .public) view=\(String(describing: self.view.frame), privacy: .public) viewOnScreen=\(String(describing: viewOnScreen), privacy: .public) root=\(String(describing: self.rootStack.frame), privacy: .public) rootOnScreen=\(String(describing: rootOnScreen), privacy: .public) heightConstraintActive=\(self.inputViewHeightConstraint?.isActive ?? false, privacy: .public) heightConstraintConstant=\(self.inputViewHeightConstraint?.constant ?? -1, privacy: .public) safeArea=\(String(describing: self.view.safeAreaInsets), privacy: .public) superview=\(superviewDescription, privacy: .public) ancestors=\(ancestorDescriptions.joined(separator: " -> "), privacy: .public) window=\(String(describing: self.view.window?.frame), privacy: .public) windowBG=\(String(describing: self.view.window?.backgroundColor), privacy: .public) ambiguous=\(ambiguityDescription, privacy: .public)"
        )
    }
#endif

    deinit {
        startupTask?.cancel()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        clearMarkedComposition()
        session?.clearComposition()
        if session != nil { compositionLabel.text = "" }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyColors()
        refresh()
    }

    private func startEngine() {
        let paths: InputServicePaths
        do {
            paths = try InputServicePaths.applicationDefaults(bundle: .main)
        } catch {
            showStartupError(error.localizedDescription)
            return
        }
        let schemaIdentifier = UserDefaults.standard.string(forKey: "schema") ?? "flypyShape"
        let schema = FengYuSchema(rawValue: schemaIdentifier) ?? .flypy
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            do {
                let result = try await KeyboardInputRuntime.shared.makeSession(paths: paths, schema: schema)
                try Task.checkCancellation()
                guard let self else { return }
                _ = result.session.selectSchema(identifier: schema.rawValue)
                service = result.service
                session = result.session
                startupErrorDescription = nil
                let elapsedMilliseconds = Int(
                    (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                )
                logger.notice(
                    "Input engine ready in \(elapsedMilliseconds, privacy: .public) ms; reused=\(result.reusedService, privacy: .public)"
                )
                refresh()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.logger.error(
                    "Input engine startup failed: \(error.localizedDescription, privacy: .public) paths.sharedData=\(paths.sharedData.path, privacy: .private) paths.userData=\(paths.userData.path, privacy: .private) paths.logs=\(paths.logs.path, privacy: .private)"
                )
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
        view.clipsToBounds = true
        // Keep the input view itself in the host compositor during height
        // negotiation. Only the keyboard content is hidden for transient
        // expanded frames, which avoids changing the host layer's alpha.
        rootStack.layer.opacity = 1

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
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            rootStack.heightAnchor.constraint(equalToConstant: Metrics.contentHeight)
        ])

        applyColors()
    }

    private func updateContentVisibility() {
        let heightDelta = abs(view.bounds.height - Metrics.inputViewHeight)
#if DEBUG
        let shouldShowContent = heightDelta < 1
        logger.notice(
            "Height negotiation hostHeight=\(self.view.bounds.height, privacy: .public) expectedHeight=\(Metrics.inputViewHeight, privacy: .public) settled=\(shouldShowContent, privacy: .public) constraintActive=\(self.inputViewHeightConstraint?.isActive ?? false, privacy: .public) constraintConstant=\(self.inputViewHeightConstraint?.constant ?? -1, privacy: .public)"
        )
#endif
    }

    private func updateHostPresentationVisibility() {
        let hostHeight = view.bounds.height
        guard hostHeight > 0 else { return }

        // Heights substantially larger than the requested keyboard height are
        // transient frames produced by _UIRemoteKeyboardWindow during a mode
        // change. Keep the extension hidden until UIKit reaches the compact
        // keyboard frame, while allowing legitimate nearby heights (for
        // example iPad keyboard variants) to remain visible.
        let isTransientExpandedFrame = hostHeight > Metrics.inputViewHeight + 100
        let shouldBeVisible = !isTransientExpandedFrame
        guard shouldBeVisible != hostPresentationVisible else { return }

        hostPresentationVisible = shouldBeVisible
        // Keep the controls interactive throughout host negotiation. The
        // extension's view tree must remain hit-testable on physical devices.
        rootStack.layer.opacity = 1
#if DEBUG
        logger.notice(
            "Host presentation visibility visible=\(shouldBeVisible, privacy: .public) hostHeight=\(hostHeight, privacy: .public) expectedHeight=\(Metrics.inputViewHeight, privacy: .public)"
        )
#endif
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
        let button = KeyboardButton(type: .system)
        configureTextButton(button, title: title, accessibilityLabel: accessibilityLabel)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeIconKey(_ symbol: String, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = KeyboardButton(type: .system)
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
        if let keyboardButton = button as? KeyboardButton {
            configureTouchFeedback(for: keyboardButton)
        }
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
            let button = KeyboardButton(type: .system)
            configureTouchFeedback(for: button)
            button.setTitle(punctuation, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 21)
            button.setTitleColor(keyForegroundColor, for: .normal)
            button.transform = CGAffineTransform(
                translationX: 0,
                y: Metrics.suggestionVerticalOffset
            )
            button.accessibilityLabel = punctuation
            button.addAction(UIAction { [weak self] _ in
                self?.performKeyFeedback(label: punctuation)
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
            let button = KeyboardButton(type: .system)
            configureTouchFeedback(for: button)
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
                self?.performKeyFeedback(label: "候选词 \(candidate.text)")
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
        performKeyFeedback(label: title)
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
        performKeyFeedback(label: "空格")
        let handled = session?.process(keyCode: 0x20) ?? false
        if !handled { textDocumentProxy.insertText(" ") }
        refresh()
    }

    @objc private func backspace() {
        performKeyFeedback(label: "删除")
        if session?.process(keyCode: 0xFF08) != true { textDocumentProxy.deleteBackward() }
        refresh()
    }

    @objc private func insertNewline() {
        performKeyFeedback(label: "换行")
        textDocumentProxy.insertText("\n")
        refresh()
    }

    @objc private func toggleASCII() {
        performKeyFeedback(label: "切换中英文")
        guard let session else { return }
        _ = session.setOption("ascii_mode", enabled: session.option("ascii_mode") != true)
        refresh()
    }

    @objc private func toggleShift() {
        performKeyFeedback(label: "大写")
        isShifted.toggle()
        rebuildCharacterRows()
    }

    @objc private func toggleLayoutMode() {
        performKeyFeedback(label: "切换键盘")
        layoutMode = layoutMode == .letters ? .numbers : .letters
        isShifted = false
        rebuildCharacterRows()
    }

    @objc private func toggleSymbolPage() {
        performKeyFeedback(label: "切换符号")
        layoutMode = layoutMode == .numbers ? .symbols : .numbers
        rebuildCharacterRows()
    }

    private func performKeyFeedback(label: String) {
#if DEBUG
        logger.notice("Key action label=\(label, privacy: .public) engineReady=\(self.session != nil, privacy: .public)")
#endif
    }

    private func configureKeyFeedback() {
        if #available(iOS 17.5, *) {
            keyFeedbackGenerator = UIImpactFeedbackGenerator(style: .light, view: view)
        } else {
            keyFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        }
        keyFeedbackGenerator?.prepare()
    }

    private func configureTouchFeedback(for button: UIButton) {
        button.removeTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
    }

    @objc private func keyTouchDown(_ sender: UIButton) {
#if DEBUG
        logger.notice(
            "Haptic requested label=\(sender.accessibilityLabel ?? sender.currentTitle ?? "unknown", privacy: .public) fullAccess=\(self.hasFullAccess, privacy: .public)"
        )
#endif
        keyFeedbackGenerator?.impactOccurred(intensity: 0.65)
        keyFeedbackGenerator?.prepare()
    }

    private func refresh() {
        guard let session else {
            if startupErrorDescription != nil {
                showStatus("引擎不可用")
            }
            asciiButton.setTitle("中", for: .normal)
            return
        }
        guard let snapshot = try? session.readSnapshot() else { return }
        asciiButton.setTitle(snapshot.status.isASCIIMode ? "英" : "中", for: .normal)
        asciiButton.accessibilityValue = snapshot.status.isASCIIMode ? "英文模式" : "中文模式"

        let composition = snapshot.composition?.text ?? ""
        let candidates = snapshot.menu.candidates.enumerated().map { (index: $0.offset, text: $0.element.text) }
        if snapshot.status.isASCIIMode || composition.isEmpty {
            clearMarkedComposition()
        } else {
            // Mirror the uncommitted code in the host text field, like the
            // native Chinese keyboards. The candidate strip below contains
            // candidates only; it does not duplicate the raw code.
            textDocumentProxy.setMarkedText(
                composition,
                selectedRange: NSRange(location: composition.utf16.count, length: 0)
            )
        }
        if composition.isEmpty && candidates.isEmpty {
            showQuickPunctuation()
        } else {
            showCandidates(candidates, composition: "")
        }
        if let commit = snapshot.commitText {
            clearMarkedComposition()
            textDocumentProxy.insertText(commit)
        }
    }

    /// Removes the temporary marked string without committing it into the host
    /// document. This is important when the final composing character is
    /// deleted: `unmarkText()` would first commit/remove its underline, making
    /// the user press Backspace twice.
    private func clearMarkedComposition() {
        textDocumentProxy.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0)
        )
    }
}

import UIKit
import OSLog

private enum KeyboardPreferences {
    static let schemaKey = "schema"
    static let appGroupIdentifier = "group.com.shendongchun.windwhisper"

    static var selectedSchemaIdentifier: String {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: schemaKey)
            ?? "flypyShape"
    }
}

private actor KeyboardInputRuntime {
    static let shared = KeyboardInputRuntime()

    private var service: InputService?
    private var loadedSchema: FengYuSchema?
    private var loadedUserData: URL?
    private var customWordsData: Data?

    func makeSession(
        paths: InputServicePaths,
        schema: FengYuSchema
    ) throws -> (service: InputService, session: InputSession, reusedService: Bool) {
        let service: InputService
        let reusedService: Bool
        if let cachedService = self.service, loadedSchema == schema,
           loadedUserData == paths.userData {
            service = cachedService
            reusedService = true
        } else {
            let loadedService = try InputService(
                paths: paths,
                enabledSchemas: [schema],
                candidateLimit: nil
            )
            self.service = loadedService
            loadedSchema = schema
            loadedUserData = paths.userData
            customWordsData = nil
            service = loadedService
            reusedService = false
        }
        return (service, try service.makeSession(), reusedService)
    }

    func reloadCustomWordsIfChanged(for expectedService: InputService) throws -> Bool {
        guard loadedSchema == .flypy, let service, service === expectedService else { return false }
        let url = service.paths.userData.appendingPathComponent("custom_words.tsv")
        let data = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
        guard data != customWordsData else { return false }
        try service.reloadCustomWords()
        customWordsData = data
        return true
    }
}

final class KeyboardViewController: UIInputViewController, UICollectionViewDataSource,
    UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    private enum LayoutMode {
        case letters
        case numbers
        case symbols
    }

    private enum SuggestionItem {
        case punctuation(String)
        case candidate(CandidateSnapshot)
        case status(String)
    }

    private final class SuggestionCell: UICollectionViewCell {
        static let reuseIdentifier = "SuggestionCell"
        #if CANDIDATE_UI_TEST
        static var creationCount = 0
        #endif
        let label = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            #if CANDIDATE_UI_TEST
            Self.creationCount += 1
            #endif
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 6
        static let suggestionToKeysSpacing: CGFloat = 7
        static let keyRowSpacing: CGFloat = 10.5
        static let keySpacing: CGFloat = 6
        static let keyHeight: CGFloat = 43
        static let utilityKeyHeight: CGFloat = 43
        static let suggestionHeight: CGFloat = 32
        static let keyCornerRadius: CGFloat = 8
        static let contentHeight: CGFloat = 247
        static let inputViewHeight: CGFloat = contentHeight + 9
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
                UIView.animate(
                    withDuration: 0.06,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: changes
                )
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
                UIView.animate(
                    withDuration: 0.1,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                    animations: changes
                )
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
    private var requestedSchemaIdentifier: String?
    private var requestedUserData: URL?
    private var layoutMode = LayoutMode.letters
    private var isShifted = false
    private var startupTask: Task<Void, Never>?
    private var hostPresentationVisible = false
    private var keyFeedbackGenerator: UIImpactFeedbackGenerator?
    private var backspaceRepeatTimer: Timer?
    private var backspaceHandledOnTouchDown = false
    private var appliedKeyboardAppearance: UIKeyboardAppearance?
    private var hasMarkedComposition = false
    private var markedCompositionText = ""
    private var customWordsRefreshTimer: Timer?
    private var hasActiveEngineComposition = false
#if DEBUG
    private var layoutLogSequence = 0
    private var lastLoggedViewBounds = CGRect.null
    private var lastLoggedRootFrame = CGRect.null
#endif

    private let rootStack = UIStackView()
    private let keyboardRowsStack = UIStackView()
    private let suggestionCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 5
        layout.minimumInteritemSpacing = 5
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private var suggestionItems = [SuggestionItem]()
    private var candidateQueryGeneration: UInt64 = 0
    private var hasMoreCandidateItems = false
    private var highlightedCandidateIndex = 0
    private var candidateLoadScheduled = false
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
        view = inputView
        self.inputView = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyFeedback()
#if DEBUG
        logger.notice(
            "Self-sizing input view allowsSelfSizing=\((self.view as? UIInputView)?.allowsSelfSizing ?? false, privacy: .public) intrinsic=\(String(describing: self.view.intrinsicContentSize), privacy: .public) initialFrame=\(String(describing: self.view.frame), privacy: .public) preferredContentSize=\(String(describing: self.preferredContentSize), privacy: .public) inputView=\(String(describing: self.inputView), privacy: .public) sameView=\(self.inputView === self.view, privacy: .public)"
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

    override func viewWillLayoutSubviews() {
        let width = view.bounds.width
        if width > 0 {
            preferredContentSize = CGSize(width: width, height: Metrics.inputViewHeight)
        }
        super.viewWillLayoutSubviews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHostPresentationVisibility()
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
        // A reused controller can still carry the previous presentation's
        // compact bounds. Wait for this presentation's layout before revealing it.
        setHostPresentationVisible(false)
        view.setNeedsLayout()
        startEngine()
#if DEBUG
        logLayoutState("viewWillAppear animated=\(animated)")
#endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startEngine()
        customWordsRefreshTimer?.invalidate()
        customWordsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            Task { @MainActor [weak self] in
                guard let self, let service = self.service, let session = self.session else { return }
                do {
                    if try await KeyboardInputRuntime.shared.reloadCustomWordsIfChanged(for: service) {
                        await MainActor.run {
                            guard self.session === session else { return }
                            self.session?.refreshCandidates()
                            self.refresh()
                        }
                    }
                } catch {
                    self.logger.error("Custom words reload failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        keyFeedbackGenerator?.prepare()
#if DEBUG
        logLayoutState("viewDidAppear animated=\(animated)")
#endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        customWordsRefreshTimer?.invalidate()
        customWordsRefreshTimer = nil
        stopRepeatingBackspace()
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
            "Layout #\(self.layoutLogSequence) \(phase, privacy: .public) view=\(String(describing: self.view.frame), privacy: .public) viewOnScreen=\(String(describing: viewOnScreen), privacy: .public) root=\(String(describing: self.rootStack.frame), privacy: .public) safeArea=\(String(describing: self.view.safeAreaInsets), privacy: .public) superview=\(superviewDescription, privacy: .public) ancestors=\(ancestorDescriptions.joined(separator: " -> "), privacy: .public) window=\(String(describing: self.view.window?.frame), privacy: .public) windowBG=\(String(describing: self.view.window?.backgroundColor), privacy: .public) ambiguous=\(ambiguityDescription, privacy: .public)"
        )
    }
#endif

    deinit {
        startupTask?.cancel()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        guard hasActiveEngineComposition || hasMarkedComposition else { return }
        clearMarkedComposition()
        session?.clearComposition()
        hasActiveEngineComposition = false
        if session != nil { showQuickPunctuation() }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyColors()
    }

    private func startEngine() {
        #if CANDIDATE_UI_TEST
        return
        #else
        let schemaIdentifier = KeyboardPreferences.selectedSchemaIdentifier
        let paths: InputServicePaths
        do {
            let defaults = try InputServicePaths.applicationDefaults(bundle: .main)
            paths = InputServicePaths(
                sharedData: defaults.sharedData,
                // The App Group is the sole source of custom words. Do not
                // silently select an empty private dictionary based on an early
                // hasFullAccess value; actual container access is authoritative.
                userData: try KeyboardSharedStorage.userDataURL(),
                logs: defaults.logs
            )
        } catch {
            requestedSchemaIdentifier = nil
            showStartupError(error.localizedDescription)
            return
        }
        let schema = FengYuSchema(rawValue: schemaIdentifier) ?? .flypy
        guard requestedSchemaIdentifier != schemaIdentifier
            || requestedUserData != paths.userData else { return }
        if requestedSchemaIdentifier == schemaIdentifier, requestedUserData == paths.userData,
           session != nil {
            return
        }
        requestedSchemaIdentifier = schemaIdentifier
        requestedUserData = paths.userData
        logger.notice(
            "Loading shared dictionary schema=\(schema.rawValue, privacy: .public) fullAccess=\(self.hasFullAccess, privacy: .public)"
        )
        clearMarkedComposition()
        session?.clearComposition()
        session = nil
        hasActiveEngineComposition = false
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            do {
                let result = try await KeyboardInputRuntime.shared.makeSession(
                    paths: paths, schema: schema
                )
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
                self?.requestedSchemaIdentifier = nil
                self?.logger.error(
                    "Input engine startup failed: \(error.localizedDescription, privacy: .public) paths.sharedData=\(paths.sharedData.path, privacy: .private) paths.userData=\(paths.userData.path, privacy: .private) paths.logs=\(paths.logs.path, privacy: .private)"
                )
                self?.showStartupError(error.localizedDescription)
            }
        }
        #endif
    }

    #if CANDIDATE_UI_TEST
    private var testLastCommit: String?
    private var testFeedbackCount = 0

    func verifyCandidateCollection(dictionary: URL) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = try InputService(paths: .temporary(root: root, sharedData: dictionary.deletingLastPathComponent()), enabledSchemas: [.flypy], candidateLimit: nil)
        service = engine
        session = try engine.makeSession()
        session?.simulate(sequence: "z")
        refresh()
        view.layoutIfNeeded()
        let baseline = SuggestionCell.creationCount
        var rounds = 0
        while hasMoreCandidateItems {
            guard rounds < 200 else { throw InputEngineError.smokeAssertion("collection did not finish loading") }
            let last = IndexPath(item: suggestionItems.count - 1, section: 0)
            suggestionCollectionView.scrollToItem(at: last, at: .right, animated: false)
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            rounds += 1
        }
        let count = suggestionItems.count
        precondition(count > 1000)
        let created = SuggestionCell.creationCount - baseline
        precondition(created < 50, "collection accumulated \(created) cells")
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            UIColor.systemGray5.setFill()
            context.fill(view.bounds)
            view.layer.render(in: context.cgContext)
        }
        try image.pngData()?.write(to: root.deletingLastPathComponent().appendingPathComponent("candidate-stress.png"))
        for selected in [5, 32, count - 1] {
            session?.clearComposition()
            session?.simulate(sequence: "z")
            while try session!.readSnapshot().menu.candidates.count <= selected {
                precondition(session!.loadMoreCandidates())
            }
            refresh()
            guard case .candidate(let expected) = suggestionItems[selected] else {
                throw InputEngineError.smokeAssertion("missing candidate")
            }
            let feedbackBeforeSelection = testFeedbackCount
            collectionView(suggestionCollectionView, didSelectItemAt: IndexPath(item: selected, section: 0))
            precondition(testLastCommit == expected.text, "wrong collection selection at \(selected)")
            precondition(testFeedbackCount == feedbackBeforeSelection + 1, "selection must trigger feedback once")
        }
        session?.simulate(sequence: "z")
        refresh()
        collectionView(suggestionCollectionView, willDisplay: SuggestionCell(frame: .zero),
                       forItemAt: IndexPath(item: suggestionItems.count - 1, section: 0))
        session?.process(keyCode: 0xFF08)
        session?.simulate(sequence: "ni")
        refresh()
        view.layoutIfNeeded()
        let newGeneration = candidateQueryGeneration
        let newCount = suggestionItems.count
        try await Task.sleep(for: .milliseconds(20))
        precondition(candidateQueryGeneration == newGeneration && suggestionItems.count == newCount)
        precondition(suggestionCollectionView.contentOffset.x == 0)
        session?.clearComposition()
        session?.simulate(sequence: "vvvvvv")
        refresh()
        precondition(suggestionItems.isEmpty && hasActiveEngineComposition)
        insertNewline()
        precondition(testLastCommit == "vvvvvv" && !hasActiveEngineComposition && !hasMarkedComposition)
        return "PASS collection: \(count) items, \(created) additional cells, \(rounds) scroll batches, selection 6/33/last, stale batch rejected, query reset, Return commits unmatched code"
    }
    #endif

    private func showStartupError(_ description: String) {
        startupErrorDescription = description
        showStatus("词库加载失败，请检查完全访问后重开键盘")
        logger.error("Input engine startup failed: \(description, privacy: .public)")
    }

    private func buildView() {
        view.backgroundColor = .clear
        view.clipsToBounds = true
        // Keep the input view itself in the host compositor during height
        // negotiation. Only the keyboard content is hidden for transient
        // expanded frames, which avoids changing the host layer's alpha.
        rootStack.layer.opacity = 0

        rootStack.axis = .vertical
        rootStack.spacing = Metrics.suggestionToKeysSpacing
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        configureSuggestionBar()
        configureKeyboardRows()
        rootStack.addArrangedSubview(suggestionCollectionView)
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

    private func updateHostPresentationVisibility() {
        let hostHeight = view.bounds.height

        // Heights substantially larger than the requested keyboard height are
        // transient frames produced by _UIRemoteKeyboardWindow during a mode
        // change. Keep the extension hidden until UIKit reaches the compact
        // keyboard frame, while allowing legitimate nearby heights (for
        // example iPad keyboard variants) to remain visible.
        let isTransientExpandedFrame = hostHeight > Metrics.inputViewHeight + 100
        let shouldBeVisible = view.window != nil
            && view.bounds.width > 0
            && hostHeight >= Metrics.contentHeight
            && !isTransientExpandedFrame
        setHostPresentationVisible(shouldBeVisible)
    }

    private func setHostPresentationVisible(_ shouldBeVisible: Bool) {
        guard shouldBeVisible != hostPresentationVisible else { return }

        hostPresentationVisible = shouldBeVisible
        // Change only the content layer, leaving the host view's alpha and
        // hit-testing intact. Do not animate or capture the temporary frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootStack.layer.opacity = shouldBeVisible ? 1 : 0
        CATransaction.commit()
#if DEBUG
        logger.notice(
            "Host presentation visibility visible=\(shouldBeVisible, privacy: .public) hostHeight=\(self.view.bounds.height, privacy: .public) expectedHeight=\(Metrics.inputViewHeight, privacy: .public)"
        )
#endif
    }

    private func configureSuggestionBar() {
        suggestionCollectionView.showsHorizontalScrollIndicator = false
        suggestionCollectionView.alwaysBounceHorizontal = true
        suggestionCollectionView.backgroundColor = .clear
        suggestionCollectionView.dataSource = self
        suggestionCollectionView.delegate = self
        suggestionCollectionView.register(
            SuggestionCell.self,
            forCellWithReuseIdentifier: SuggestionCell.reuseIdentifier
        )
        suggestionCollectionView.heightAnchor.constraint(
            equalToConstant: Metrics.suggestionHeight
        ).isActive = true

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
            rows = usesChineseSymbols ? [
                Array("1234567890").map(String.init),
                ["－", "／", "：", "；", "（", "）", "￥", "＆", "＠"],
                ["。", "，", "？", "！", "‘’", "“”"]
            ] : [
                Array("1234567890").map(String.init),
                ["-", "/", ":", ";", "(", ")", "$", "&", "@"],
                [".", ",", "?", "!", "'", "\""]
            ]
        case .symbols:
            rows = usesChineseSymbols ? [
                ["【", "】", "｛", "｝", "＃", "％", "＾", "＊", "＋", "＝"],
                ["＿", "＼", "｜", "～", "《", "》", "€", "£", "￥"],
                ["·", "……", "，", "。", "？", "！"]
            ] : [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "€", "£", "¥"],
                ["·", "…", ",", ".", "?", "!"]
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

        let backspace = makeIconKey(
            "delete.left",
            accessibilityLabel: "删除",
            action: #selector(finishBackspace(_:))
        )
        backspace.addTarget(self, action: #selector(beginBackspace(_:)), for: .touchDown)
        for event: UIControl.Event in [.touchUpOutside, .touchCancel, .touchDragExit] {
            backspace.addTarget(self, action: #selector(stopRepeatingBackspace), for: event)
        }
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
        let appearance = textDocumentProxy.keyboardAppearance
        guard appearance != appliedKeyboardAppearance else { return }
        appliedKeyboardAppearance = appearance
        view.backgroundColor = .clear
        suggestionCollectionView.backgroundColor = .clear
        suggestionCollectionView.reloadData()
        findButtons(in: rootStack).forEach { button in
            if button === asciiButton {
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

    private var usesChineseSymbols: Bool {
        session?.option("ascii_mode") != true
    }

    private func showQuickPunctuation() {
        let punctuationKeys: [String] = usesChineseSymbols
            ? ["，", "。", "？", "！", "、", "……"]
            : [",", ".", "?", "!", "\\", "…"]
        suggestionItems = punctuationKeys.map(SuggestionItem.punctuation)
        hasMoreCandidateItems = false
        reloadSuggestions(resetPosition: true)
    }

    private func showCandidates(
        _ candidates: [CandidateSnapshot],
        resetPosition: Bool
    ) {
        let oldCount = suggestionItems.count
        suggestionItems = candidates.map(SuggestionItem.candidate)
        if !resetPosition, candidates.count > oldCount {
            suggestionCollectionView.insertItems(at: (oldCount..<candidates.count).map { IndexPath(item: $0, section: 0) })
        } else {
            reloadSuggestions(resetPosition: resetPosition)
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        _ = collectionView
        _ = section
        return suggestionItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SuggestionCell.reuseIdentifier,
            for: indexPath
        ) as! SuggestionCell
        let item = suggestionItems[indexPath.item]
        let selected: Bool
        if case .candidate = item { selected = indexPath.item == highlightedCandidateIndex }
        else { selected = false }
        switch item {
        case .punctuation(let text):
            cell.label.text = text
            cell.label.font = .systemFont(ofSize: 21)
            cell.accessibilityLabel = text
        case .candidate(let candidate):
            cell.label.text = candidate.comment.map { "\(candidate.text) \($0)" } ?? candidate.text
            cell.label.font = .systemFont(ofSize: 19)
            cell.accessibilityLabel = "候选词 \(candidate.text)"
        case .status(let text):
            cell.label.text = text
            cell.label.font = .systemFont(ofSize: 15, weight: .medium)
            cell.accessibilityLabel = text
        }
        cell.label.textColor = keyForegroundColor
        cell.contentView.backgroundColor = selected ? selectedCandidateBackgroundColor : .clear
        cell.contentView.layer.cornerRadius = selected ? 8 : 0
        cell.accessibilityTraits = selected ? [.button, .selected] : .button
        cell.isAccessibilityElement = true
        if case .status = item { cell.accessibilityTraits = .staticText }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch suggestionItems[indexPath.item] {
        case .punctuation(let punctuation):
            playKeyFeedback()
            insertPunctuation(punctuation)
        case .candidate:
            let selected = session?.selectCandidate(
                atAbsoluteIndex: indexPath.item,
                generation: candidateQueryGeneration
            ) ?? false
            if selected { playKeyFeedback() }
            refresh()
        case .status:
            break
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        _ = collectionViewLayout
        let text: String
        switch suggestionItems[indexPath.item] {
        case .punctuation(let value), .status(let value): text = value
        case .candidate(let value): text = value.comment.map { "\(value.text) \($0)" } ?? value.text
        }
        let width = ceil((text as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 19)
        ]).width) + 20
        return CGSize(width: max(50, width), height: 28)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        _ = cell
        guard hasMoreCandidateItems, !candidateLoadScheduled,
              indexPath.item >= max(0, suggestionItems.count - 8)
        else { return }
        candidateLoadScheduled = true
        let generation = candidateQueryGeneration
        let currentSession = session
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.candidateLoadScheduled = false
            guard self.session === currentSession, self.candidateQueryGeneration == generation else { return }
            _ = self.session?.loadMoreCandidates(generation: generation)
            self.refresh()
        }
    }

    private func showStatus(_ message: String) {
        suggestionItems = [.status(message)]
        hasMoreCandidateItems = false
        reloadSuggestions(resetPosition: true)
    }

    private func reloadSuggestions(resetPosition: Bool) {
        suggestionCollectionView.reloadData()
        if resetPosition, !suggestionItems.isEmpty {
            suggestionCollectionView.setContentOffset(.zero, animated: false)
        }
    }

    private func insertPunctuation(_ punctuation: String) {
        textDocumentProxy.insertText(punctuation)
    }

    private var selectedCandidateBackgroundColor: UIColor {
        textDocumentProxy.keyboardAppearance == .dark
            ? UIColor.white.withAlphaComponent(0.16)
            : .white
    }

    @objc private func keyPressed(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }
        guard layoutMode == .letters else {
            textDocumentProxy.insertText(title)
            return
        }
        guard let value = title.lowercased().first else { return }
        let output = isShifted ? String(value).uppercased() : String(value)
        let keyCode = Int32(output.utf8.first ?? 0)
        let handled = session?.process(keyCode: keyCode) ?? false
        if !handled { textDocumentProxy.insertText(output) }
        if isShifted {
            isShifted = false
            rebuildCharacterRows()
        }
        if handled { refresh() }
    }

    @objc private func space() {
        let handled = session?.process(keyCode: 0x20) ?? false
        if !handled { textDocumentProxy.insertText(" ") }
        if handled { refresh() }
    }

    @objc private func beginBackspace(_ sender: UIButton) {
        _ = sender
        stopRepeatingBackspace()
        backspaceHandledOnTouchDown = true
        deleteBackwardOnce()

        let timer = Timer(timeInterval: 0.055, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deleteBackwardOnce()
            }
        }
        timer.fireDate = Date().addingTimeInterval(0.22)
        RunLoop.main.add(timer, forMode: .common)
        backspaceRepeatTimer = timer
    }

    @objc private func finishBackspace(_ sender: UIButton) {
        _ = sender
        if !backspaceHandledOnTouchDown {
            deleteBackwardOnce()
        }
        stopRepeatingBackspace()
        backspaceHandledOnTouchDown = false
    }

    @objc private func stopRepeatingBackspace() {
        backspaceRepeatTimer?.invalidate()
        backspaceRepeatTimer = nil
    }

    private func deleteBackwardOnce() {
        if hasActiveEngineComposition,
           session?.process(keyCode: 0xFF08) == true {
            refresh()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    @objc private func insertNewline() {
        let handled = session?.process(keyCode: 0xFF0D) ?? false
        refresh()
        if !handled { textDocumentProxy.insertText("\n") }
    }

    @objc private func toggleASCII() {
        guard let session else { return }
        _ = session.setOption("ascii_mode", enabled: session.option("ascii_mode") != true)
        if layoutMode != .letters { rebuildCharacterRows() }
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

    private func configureKeyFeedback() {
        if #available(iOS 17.5, *) {
            keyFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium, view: view)
        } else {
            keyFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        }
        keyFeedbackGenerator?.prepare()
    }

    private func configureTouchFeedback(for button: UIButton) {
        button.removeTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
    }

    @objc private func keyTouchDown(_ sender: UIButton) {
        _ = sender
        playKeyFeedback()
    }

    private func playKeyFeedback() {
        #if CANDIDATE_UI_TEST
        testFeedbackCount += 1
        #endif
        keyFeedbackGenerator?.impactOccurred(intensity: 0.9)
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
        hasActiveEngineComposition = !composition.isEmpty
        let isNewQuery = candidateQueryGeneration != snapshot.menu.queryGeneration
        candidateQueryGeneration = snapshot.menu.queryGeneration
        hasMoreCandidateItems = snapshot.menu.hasMoreCandidates
        highlightedCandidateIndex = snapshot.menu.highlightedIndex
        let candidates = snapshot.menu.candidates
        if snapshot.status.isASCIIMode || composition.isEmpty {
            clearMarkedComposition()
        } else if !hasMarkedComposition || markedCompositionText != composition {
            // Mirror the uncommitted code in the host text field, like the
            // native Chinese keyboards. The candidate strip below contains
            // candidates only; it does not duplicate the raw code.
            textDocumentProxy.setMarkedText(
                composition,
                selectedRange: NSRange(location: composition.utf16.count, length: 0)
            )
            hasMarkedComposition = true
            markedCompositionText = composition
        }
        if composition.isEmpty && candidates.isEmpty {
            showQuickPunctuation()
        } else {
            showCandidates(candidates, resetPosition: isNewQuery)
        }
        if let commit = snapshot.commitText {
            #if CANDIDATE_UI_TEST
            testLastCommit = commit
            #endif
            clearMarkedComposition()
            textDocumentProxy.insertText(commit)
        }
    }

    /// Removes the temporary marked string without committing it into the host
    /// document. This is important when the final composing character is
    /// deleted: `unmarkText()` would first commit/remove its underline, making
    /// the user press Backspace twice.
    private func clearMarkedComposition() {
        guard hasMarkedComposition else { return }
        textDocumentProxy.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        hasMarkedComposition = false
        markedCompositionText = ""
    }
}

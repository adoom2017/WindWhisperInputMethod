import AppKit
import InputMethodKit
import OSLog

final class RimeInputController: IMKInputController, @unchecked Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? InputSourceMetadata.bundleIdentifier,
        category: "InputController"
    )

    private weak var inputClient: IMKTextInput?
    private var session: RimeSession?
    private var hasMarkedText = false
    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var didLogSessionError = false
    private var settingsObservers = [NSObjectProtocol]()
    private lazy var candidateWindow = CandidateWindowCoordinator { [weak self] action in
        self?.handleCandidateWindowAction(action)
    }
    private lazy var inputModeIndicator = InputModeIndicatorCoordinator()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        self.inputClient = inputClient as? IMKTextInput
        super.init(server: server, delegate: delegate, client: inputClient)
        observeSettings()
        ensureSession()
    }

    deinit {
        removeSettingsObservers()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(
            NSEvent.EventTypeMask.keyDown.rawValue
                | NSEvent.EventTypeMask.flagsChanged.rawValue
        )
    }

    override func menu() -> NSMenu! {
        FengYuSettingsMenuController.shared.menu
    }

    override func activateServer(_ sender: Any!) {
        inputClient = sender as? IMKTextInput
        lastModifierFlags = Self.currentCapsLockFlags()
        ensureSession()
        logger.debug("Input session activated")
    }

    override func deactivateServer(_ sender: Any!) {
        if let sender = sender as? IMKTextInput {
            inputClient = sender
        }
        finishComposition()
        hideInputModeIndicator()
        inputClient = nil
        logger.debug("Input session deactivated")
    }

    override func inputControllerWillClose() {
        finishComposition()
        hideCandidateWindow()
        hideInputModeIndicator()
        removeSettingsObservers()
        session = nil
        inputClient = nil
        super.inputControllerWillClose()
    }

    override func commitComposition(_ sender: Any!) {
        if let sender = sender as? IMKTextInput {
            inputClient = sender
        }
        finishComposition()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            return false
        }
        if let senderClient = sender as? IMKTextInput {
            inputClient = senderClient
        }
        guard let client = inputClient else {
            logger.debug("Key passed through because no IMK text client is available")
            return false
        }
        ensureSession()

        if event.type == .flagsChanged {
            return handleModifierFlagsChanged(event, session: session, client: client)
        }
        guard let mappedKey = RimeKeyMapper.map(event) else {
            return false
        }
        guard let session else {
            logger.debug("Key passed through because no Rime session is available")
            return false
        }
        guard session.process(keyCode: mappedKey.keyCode, modifierMask: mappedKey.modifierMask) else {
            return false
        }

        do {
            let snapshot = try session.readSnapshot()
            apply(snapshot, to: client)
        } catch {
            logger.error("Unable to update composition: \(error.localizedDescription, privacy: .public)")
            session.clearComposition()
            hasMarkedText = RimeClientUpdater.clearMarkedText(in: client)
            hideCandidateWindow()
        }
        return true
    }

    private func handleModifierFlagsChanged(
        _ event: NSEvent,
        session: RimeSession?,
        client: IMKTextInput
    ) -> Bool {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let changes = lastModifierFlags.symmetricDifference(modifierFlags)
        lastModifierFlags = modifierFlags
        guard changes.isEmpty == false else {
            return true
        }
        guard let mappedKey = RimeKeyMapper.mapModifierChange(
            keyCode: event.keyCode,
            modifierFlags: modifierFlags,
            changedFlags: changes
        ), let session else {
            return false
        }

        let previousASCIIMode = session.option("ascii_mode")
        let handled = session.process(
            keyCode: mappedKey.keyCode,
            modifierMask: mappedKey.modifierMask
        )
        do {
            let snapshot = try session.readSnapshot()
            apply(snapshot, to: client)
            if let previousASCIIMode,
                let indicatorState = InputModeIndicatorTransition.state(
                    before: previousASCIIMode,
                    after: snapshot.status.isASCIIMode
                )
            {
                presentInputModeIndicator(indicatorState, client: client)
            }
        } catch {
            logger.error("Unable to refresh modifier state: \(error.localizedDescription, privacy: .public)")
        }
        return handled
    }

    private static func currentCapsLockFlags() -> NSEvent.ModifierFlags {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            ? .capsLock
            : []
    }

    private func ensureSession() {
        guard session == nil else {
            return
        }
        do {
            session = try RimeRuntime.shared.makeSession()
            didLogSessionError = false
        } catch {
            if !didLogSessionError {
                logger.error("Unable to create Rime session: \(error.localizedDescription, privacy: .public)")
                didLogSessionError = true
            }
        }
    }

    private func observeSettings() {
        let center = NotificationCenter.default
        settingsObservers = [
            center.addObserver(
                forName: .fengYuSettingsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applyChangedSettings()
            },
            center.addObserver(
                forName: .fengYuWillRedeploy,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.prepareForRedeploy()
            },
            center.addObserver(
                forName: .fengYuDidRedeploy,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.ensureSession()
            },
        ]
    }

    private func removeSettingsObservers() {
        let center = NotificationCenter.default
        settingsObservers.forEach(center.removeObserver)
        settingsObservers.removeAll()
    }

    private func applyChangedSettings() {
        finishComposition()
        guard let session else {
            ensureSession()
            return
        }
        do {
            try FengYuSettingsStore.shared.snapshot.apply(to: session)
            didLogSessionError = false
        } catch {
            logger.error("Unable to apply settings: \(error.localizedDescription, privacy: .public)")
            self.session = nil
        }
    }

    private func prepareForRedeploy() {
        finishComposition()
        hideCandidateWindow()
        hideInputModeIndicator()
        session = nil
    }

    private func finishComposition() {
        hideCandidateWindow()
        guard let session, let client = inputClient else {
            hasMarkedText = false
            return
        }

        if session.commitComposition() {
            do {
                apply(try session.readSnapshot(), to: client)
                return
            } catch {
                logger.error("Unable to commit composition: \(error.localizedDescription, privacy: .public)")
            }
        }

        session.clearComposition()
        hasMarkedText = RimeClientUpdater.clearMarkedText(in: client)
    }

    private func apply(_ snapshot: RimeSnapshot, to client: IMKTextInput) {
        hasMarkedText = RimeClientUpdater.apply(
            snapshot,
            to: client,
            hadMarkedText: hasMarkedText
        )
        updateCandidateWindow(snapshot: snapshot, client: client)
    }

    private func updateCandidateWindow(snapshot: RimeSnapshot, client: IMKTextInput) {
        guard snapshot.composition != nil, !snapshot.menu.candidates.isEmpty else {
            hideCandidateWindow()
            return
        }

        guard let anchorRect = CandidateAnchorResolver.anchorRect(in: client) else {
            #if DEBUG
                logger.notice(
                    "Candidate panel suppressed: no usable anchor; candidates=\(snapshot.menu.candidates.count)"
                )
            #endif
            hideCandidateWindow()
            return
        }

        presentCandidateWindow(
            menu: snapshot.menu,
            anchorRect: anchorRect,
            clientWindowLevel: client.windowLevel()
        )
    }

    private func handleCandidateWindowAction(_ action: CandidateWindowAction) {
        guard let session, let client = inputClient else {
            hideCandidateWindow()
            return
        }

        let accepted: Bool
        switch action {
        case .selectCandidate(let index):
            accepted = session.selectCandidate(at: index)
        case .page(let up):
            accepted = session.process(keyCode: up ? 0xFF55 : 0xFF56)
        }
        guard accepted else {
            return
        }

        do {
            apply(try session.readSnapshot(), to: client)
        } catch {
            logger.error("Unable to apply candidate selection: \(error.localizedDescription, privacy: .public)")
            session.clearComposition()
            hasMarkedText = RimeClientUpdater.clearMarkedText(in: client)
            hideCandidateWindow()
        }
    }

    private func presentCandidateWindow(
        menu: RimeMenuSnapshot,
        anchorRect: NSRect,
        clientWindowLevel: CGWindowLevel
    ) {
        let operation: () -> Void = { [weak self] in
            guard let self else { return }
            self.candidateWindow.update(
                menu: menu,
                anchorRect: anchorRect,
                clientWindowLevel: clientWindowLevel
            )
        }
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }

    private func hideCandidateWindow() {
        let operation: () -> Void = { [weak self] in
            guard let self else { return }
            self.candidateWindow.hide()
        }
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }

    private func presentInputModeIndicator(
        _ state: InputModeIndicatorState,
        client: IMKTextInput
    ) {
        guard let anchorRect = CandidateAnchorResolver.anchorRect(in: client) else {
            hideInputModeIndicator()
            return
        }
        let clientWindowLevel = client.windowLevel()
        let operation: () -> Void = { [weak self] in
            self?.inputModeIndicator.show(
                state: state,
                anchorRect: anchorRect,
                clientWindowLevel: clientWindowLevel
            )
        }
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }

    private func hideInputModeIndicator() {
        let operation: () -> Void = { [weak self] in
            self?.inputModeIndicator.hide()
        }
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}

extension RimeInputController {
    @objc func fengYuSelectSchemaCommand(_ command: Any) {
        guard let menuItem = fengYuMenuItem(from: command) else {
            return
        }
        FengYuSettingsMenuController.shared.selectSchema(menuItem: menuItem)
    }

    @objc func fengYuToggleFullWidthCommand(_ command: Any) {
        FengYuSettingsMenuController.shared.toggleFullWidth()
    }

    @objc func fengYuToggleSimplifiedChineseCommand(_ command: Any) {
        FengYuSettingsMenuController.shared.toggleSimplifiedChinese()
    }

    @objc func fengYuSelectOrientationCommand(_ command: Any) {
        guard let menuItem = fengYuMenuItem(from: command) else {
            return
        }
        FengYuSettingsMenuController.shared.selectOrientation(menuItem: menuItem)
    }

    @objc func fengYuSelectColorSchemeCommand(_ command: Any) {
        guard let menuItem = fengYuMenuItem(from: command) else {
            return
        }
        FengYuSettingsMenuController.shared.selectColorScheme(menuItem: menuItem)
    }

    @objc func fengYuRedeployCommand(_ command: Any) {
        FengYuSettingsMenuController.shared.redeploy()
    }

    @objc func fengYuOpenUserDirectoryCommand(_ command: Any) {
        FengYuSettingsMenuController.shared.openUserDirectory()
    }

    @objc func fengYuShowDiagnosticsCommand(_ command: Any) {
        FengYuSettingsMenuController.shared.showDiagnostics()
    }

    @objc func fengYuResetSettingsCommand(_ command: Any) {
        FengYuSettingsMenuController.shared.resetSettings()
    }

    private func fengYuMenuItem(from command: Any) -> NSMenuItem? {
        if let menuItem = command as? NSMenuItem {
            return menuItem
        }
        guard let dictionary = command as? NSDictionary else {
            return nil
        }
        return dictionary.object(forKey: kIMKCommandMenuItemName) as? NSMenuItem
    }
}

enum CandidateAnchorResolver {
    static func anchorRect(in client: IMKTextInput) -> NSRect? {
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        if isUsable(lineRect) {
            return lineRect
        }

        var ranges = [NSRange(location: NSNotFound, length: 0)]
        let selectedRange = client.selectedRange()
        if selectedRange.location != NSNotFound {
            ranges.append(selectedRange)
        }
        let markedRange = client.markedRange()
        if markedRange.location != NSNotFound {
            ranges.append(NSRange(location: NSMaxRange(markedRange), length: 0))
        }

        for range in ranges {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(forCharacterRange: range, actualRange: &actualRange)
            if isUsable(rect) {
                return rect
            }
        }
        return nil
    }

    private static func isUsable(_ rect: NSRect) -> Bool {
        guard !rect.isNull, !rect.isInfinite, rect.height > 0 else {
            return false
        }
        return [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
    }
}

enum RimeClientUpdater {
    @discardableResult
    static func apply(
        _ snapshot: RimeSnapshot,
        to client: IMKTextInput,
        hadMarkedText: Bool
    ) -> Bool {
        var hasMarkedText = hadMarkedText
        if let commitText = snapshot.commitText, !commitText.isEmpty {
            client.insertText(commitText, replacementRange: replacementRange)
            hasMarkedText = false
        }

        guard let composition = snapshot.composition else {
            if hasMarkedText {
                return clearMarkedText(in: client)
            }
            return false
        }

        let markedText = NSAttributedString(string: composition.text)
        let cursor = min(max(composition.cursorPosition, 0), markedText.length)
        client.setMarkedText(
            markedText,
            selectionRange: NSRange(location: cursor, length: 0),
            replacementRange: replacementRange
        )
        return true
    }

    @discardableResult
    static func clearMarkedText(in client: IMKTextInput) -> Bool {
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: replacementRange
        )
        return false
    }

    private static let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)
}

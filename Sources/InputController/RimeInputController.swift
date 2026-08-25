import AppKit
import InputMethodKit
import OSLog

final class RimeInputController: IMKInputController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? InputSourceMetadata.bundleIdentifier,
        category: "InputController"
    )

    private weak var inputClient: IMKTextInput?
    private var session: RimeSession?
    private var hasMarkedText = false
    private var didLogSessionError = false
    private lazy var candidateWindow = CandidateWindowCoordinator { [weak self] action in
        self?.handleCandidateWindowAction(action)
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        self.inputClient = inputClient as? IMKTextInput
        super.init(server: server, delegate: delegate, client: inputClient)
        ensureSession()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        inputClient = sender as? IMKTextInput
        ensureSession()
        logger.debug("Input session activated")
    }

    override func deactivateServer(_ sender: Any!) {
        if let sender = sender as? IMKTextInput {
            inputClient = sender
        }
        finishComposition()
        inputClient = nil
        logger.debug("Input session deactivated")
    }

    override func inputControllerWillClose() {
        finishComposition()
        hideCandidateWindow()
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

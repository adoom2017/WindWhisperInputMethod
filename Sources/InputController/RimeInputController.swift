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

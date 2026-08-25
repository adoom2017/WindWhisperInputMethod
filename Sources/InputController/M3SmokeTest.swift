import AppKit
import Carbon
import Foundation

enum M3SmokeTest {
    static func run() -> Int32 {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RimeInputMethod-M3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        do {
            try verifyKeyMapping()
            print("keyMapping=passed")
            try verifyShortcutPassthrough()
            print("shortcutPassthrough=passed")
            try verifyShiftTapRecognition()
            print("shiftTapRecognition=passed")
            try verifyCompositionEditing(root: temporaryRoot)
            print("compositionEditing=passed")
            try verifyShiftModeSwitch(root: temporaryRoot)
            print("shiftModeSwitch=passed")
            try verifyFrontendCommit(root: temporaryRoot)
            print("frontendCommit=passed")
            try verifyInputClientFlow(root: temporaryRoot.appendingPathComponent("client", isDirectory: true))
            print("inputClientFlow=passed")
            return EXIT_SUCCESS
        } catch {
            fputs("M3 smoke test failed: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func verifyKeyMapping() throws {
        let letter = try requireEvent(character: "n", keyCode: UInt16(kVK_ANSI_N))
        guard RimeKeyMapper.map(letter) == RimeMappedKey(keyCode: 0x6E, modifierMask: 0) else {
            throw RimeBridgeError.smokeAssertion("ASCII letter mapping is incorrect.")
        }

        let backspace = try requireEvent(character: "\u{7F}", keyCode: UInt16(kVK_Delete))
        guard RimeKeyMapper.map(backspace)?.keyCode == 0xFF08 else {
            throw RimeBridgeError.smokeAssertion("Backspace mapping is incorrect.")
        }
    }

    private static func verifyShortcutPassthrough() throws {
        for flags: NSEvent.ModifierFlags in [.command, .control, .option] {
            let event = try requireEvent(character: "n", keyCode: UInt16(kVK_ANSI_N), flags: flags)
            guard RimeKeyMapper.map(event) == nil else {
                throw RimeBridgeError.smokeAssertion("A system shortcut was not passed through.")
            }
        }
    }

    private static func verifyShiftTapRecognition() throws {
        var tracker = ShiftTapTracker()
        guard !tracker.update(keyCode: UInt16(kVK_Shift), modifierFlags: .shift),
            tracker.update(keyCode: UInt16(kVK_Shift), modifierFlags: [])
        else {
            throw RimeBridgeError.smokeAssertion("A left Shift tap was not recognized exactly once.")
        }

        guard !tracker.update(keyCode: UInt16(kVK_RightShift), modifierFlags: .shift),
            tracker.update(keyCode: UInt16(kVK_RightShift), modifierFlags: [])
        else {
            throw RimeBridgeError.smokeAssertion("A right Shift tap was not recognized exactly once.")
        }

        guard !tracker.update(keyCode: UInt16(kVK_Shift), modifierFlags: .shift) else {
            throw RimeBridgeError.smokeAssertion("Shift toggled on key-down.")
        }
        tracker.noteKeyDown()
        guard !tracker.update(keyCode: UInt16(kVK_Shift), modifierFlags: []) else {
            throw RimeBridgeError.smokeAssertion("Shift-modified typing triggered a mode switch.")
        }

        guard !tracker.update(keyCode: UInt16(kVK_Shift), modifierFlags: .shift),
            !tracker.update(
                keyCode: UInt16(kVK_Command),
                modifierFlags: [.shift, .command]
            ),
            !tracker.update(keyCode: UInt16(kVK_Shift), modifierFlags: .command)
        else {
            throw RimeBridgeError.smokeAssertion("A system shortcut triggered a mode switch.")
        }
    }

    private static func verifyCompositionEditing(root: URL) throws {
        let session = try makeSession(root: root.appendingPathComponent("editing", isDirectory: true))
        try process(character: "n", keyCode: UInt16(kVK_ANSI_N), in: session)
        try process(character: "i", keyCode: UInt16(kVK_ANSI_I), in: session)
        guard try session.readSnapshot().composition?.text == "ni" else {
            throw RimeBridgeError.smokeAssertion("The expected marked text was not created.")
        }

        try process(character: "\u{7F}", keyCode: UInt16(kVK_Delete), in: session)
        guard try session.readSnapshot().composition?.text == "n" else {
            throw RimeBridgeError.smokeAssertion("Backspace did not edit the composition.")
        }

        try process(character: "\u{1B}", keyCode: UInt16(kVK_Escape), in: session)
        guard try session.readSnapshot().composition == nil else {
            throw RimeBridgeError.smokeAssertion("Escape did not clear the composition.")
        }
    }

    private static func verifyShiftModeSwitch(root: URL) throws {
        let session = try makeSession(root: root.appendingPathComponent("shift", isDirectory: true))
        guard session.option("ascii_mode") == false else {
            throw RimeBridgeError.smokeAssertion("The session did not start in Chinese mode.")
        }
        guard session.simulate(sequence: "ni") else {
            throw RimeBridgeError.smokeAssertion("Could not prepare a composition for Shift.")
        }
        let switched = try RimeInputModeSwitcher.toggle(in: session)
        guard switched.snapshot.status.isASCIIMode, switched.codeToCommit == "ni",
            switched.snapshot.composition == nil
        else {
            throw RimeBridgeError.smokeAssertion("Shift did not commit the code and enter English mode.")
        }
        guard !session.process(keyCode: 0x61) else {
            throw RimeBridgeError.smokeAssertion("English mode did not pass a letter through to macOS.")
        }
        let english = try session.readSnapshot()
        guard english.commitText == nil, english.composition == nil else {
            throw RimeBridgeError.smokeAssertion("English mode unexpectedly composed ASCII text.")
        }
        let restored = try RimeInputModeSwitcher.toggle(in: session)
        guard !restored.snapshot.status.isASCIIMode, restored.codeToCommit == nil else {
            throw RimeBridgeError.smokeAssertion("A second Shift tap did not restore Chinese mode.")
        }
    }

    private static func verifyFrontendCommit(root: URL) throws {
        let session = try makeSession(root: root.appendingPathComponent("commit", isDirectory: true))
        for (character, keyCode) in [
            ("n", UInt16(kVK_ANSI_N)),
            ("i", UInt16(kVK_ANSI_I)),
            ("h", UInt16(kVK_ANSI_H)),
            ("a", UInt16(kVK_ANSI_A)),
            ("o", UInt16(kVK_ANSI_O)),
            (" ", UInt16(kVK_Space)),
        ] {
            try process(character: character, keyCode: keyCode, in: session)
        }
        guard try session.readSnapshot().commitText == "你好" else {
            throw RimeBridgeError.smokeAssertion("The frontend sequence did not commit the expected text.")
        }
    }

    private static func verifyInputClientFlow(root: URL) throws {
        let client = M3InputClientDouble()
        let session = try makeSession(root: root)
        var hasMarkedText = false

        func processAndPublish(_ character: String, keyCode: UInt16) throws {
            try process(character: character, keyCode: keyCode, in: session)
            hasMarkedText = RimeClientUpdater.apply(
                try session.readSnapshot(),
                to: client,
                hadMarkedText: hasMarkedText
            )
        }

        for (character, keyCode) in [
            ("n", UInt16(kVK_ANSI_N)),
            ("i", UInt16(kVK_ANSI_I)),
        ] {
            try processAndPublish(character, keyCode: keyCode)
        }
        guard client.markedText == "ni" else {
            throw RimeBridgeError.smokeAssertion("The frontend did not publish marked text.")
        }

        try processAndPublish("\u{7F}", keyCode: UInt16(kVK_Delete))
        guard client.markedText == "n" else {
            throw RimeBridgeError.smokeAssertion("The frontend did not update marked text after Backspace.")
        }

        try processAndPublish("\u{1B}", keyCode: UInt16(kVK_Escape))
        guard client.markedText.isEmpty else {
            throw RimeBridgeError.smokeAssertion("The frontend did not clear marked text after Escape.")
        }

        for (character, keyCode) in [
            ("n", UInt16(kVK_ANSI_N)),
            ("i", UInt16(kVK_ANSI_I)),
            ("h", UInt16(kVK_ANSI_H)),
            ("a", UInt16(kVK_ANSI_A)),
            ("o", UInt16(kVK_ANSI_O)),
            (" ", UInt16(kVK_Space)),
        ] {
            try processAndPublish(character, keyCode: keyCode)
        }
        guard client.committedText == "你好", client.markedText.isEmpty else {
            throw RimeBridgeError.smokeAssertion("The frontend did not commit text to its IMK client.")
        }
    }

    private static func makeSession(root: URL) throws -> RimeSession {
        let paths = try RimeServicePaths.applicationDefaults()
        let service = try RimeService(paths: .temporary(root: root, sharedData: paths.sharedData))
        try service.deploy(fullCheck: true)
        let session = try service.makeSession()
        guard session.selectSchema(identifier: "luna_pinyin") else {
            throw RimeBridgeError.smokeAssertion("M3 could not select its full pinyin fixture")
        }
        return session
    }

    private static func process(character: String, keyCode: UInt16, in session: RimeSession) throws {
        let event = try requireEvent(character: character, keyCode: keyCode)
        guard let mapped = RimeKeyMapper.map(event) else {
            throw RimeBridgeError.smokeAssertion("A test key could not be mapped.")
        }
        guard session.process(keyCode: mapped.keyCode, modifierMask: mapped.modifierMask) else {
            throw RimeBridgeError.smokeAssertion("librime rejected a mapped test key.")
        }
    }

    private static func requireEvent(
        character: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            )
        else {
            throw RimeBridgeError.smokeAssertion("A synthetic key event could not be created.")
        }
        return event
    }
}

final class M3InputClientDouble: NSObject, IMKTextInput {
    private(set) var committedText = ""
    private(set) var markedText = ""
    var lineHeightRectangle = NSRect.zero
    var firstRectResult = NSRect.zero

    func insertText(_ string: Any!, replacementRange: NSRange) {
        committedText.append(text(from: string))
        markedText = ""
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        markedText = text(from: string)
    }

    func selectedRange() -> NSRange {
        NSRange(location: committedText.utf16.count, length: 0)
    }

    func markedRange() -> NSRange {
        guard !markedText.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: committedText.utf16.count, length: markedText.utf16.count)
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        NSAttributedString(string: substring(in: range))
    }

    func length() -> Int {
        (committedText + markedText).utf16.count
    }

    func characterIndex(
        for point: NSPoint,
        tracking mappingMode: IMKLocationToOffsetMappingMode,
        inMarkedRange: UnsafeMutablePointer<ObjCBool>!
    ) -> Int {
        inMarkedRange?.pointee = false
        return 0
    }

    func attributes(
        forCharacterIndex index: Int,
        lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!
    ) -> [AnyHashable: Any]! {
        lineRect?.pointee = lineHeightRectangle
        return [:]
    }

    func validAttributesForMarkedText() -> [Any]! {
        []
    }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}

    func selectMode(_ modeIdentifier: String!) {}

    func supportsUnicode() -> Bool {
        true
    }

    func bundleIdentifier() -> String! {
        "com.shendongchun.inputmethod.rime.m3-smoke"
    }

    func windowLevel() -> CGWindowLevel {
        CGWindowLevelForKey(.normalWindow)
    }

    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool {
        false
    }

    func uniqueClientIdentifierString() -> String! {
        "RimeInputMethod-M3-Smoke"
    }

    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        actualRange?.pointee = range
        return substring(in: range)
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect {
        actualRange?.pointee = range
        return firstRectResult
    }

    private func text(from value: Any?) -> String {
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        return value as? String ?? ""
    }

    private func substring(in range: NSRange) -> String {
        let text = committedText + markedText
        guard
            range.location != NSNotFound,
            range.location <= text.utf16.count,
            NSMaxRange(range) <= text.utf16.count,
            let swiftRange = Range(range, in: text)
        else {
            return ""
        }
        return String(text[swiftRange])
    }
}

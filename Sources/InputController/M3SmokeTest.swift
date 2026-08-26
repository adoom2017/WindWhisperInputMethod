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
            try verifyShortcutMapping()
            print("shortcutMapping=passed")
            try verifyModifierMapping()
            print("modifierMapping=passed")
            try verifyInputModeIndicatorTransition()
            print("inputModeIndicatorTransition=passed")
            try verifyCompositionEditing(root: temporaryRoot)
            print("compositionEditing=passed")
            try verifyShiftModeSwitch(root: temporaryRoot)
            print("shiftModeSwitch=passed")
            try verifyRimeShortcutRouting(root: temporaryRoot)
            print("rimeShortcutRouting=passed")
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

    private static func verifyShortcutMapping() throws {
        let command = try requireEvent(
            character: "n",
            keyCode: UInt16(kVK_ANSI_N),
            flags: .command
        )
        guard RimeKeyMapper.map(command) == nil else {
            throw RimeBridgeError.smokeAssertion("A Command shortcut was not passed through.")
        }

        let control = try requireEvent(
            character: "j",
            keyCode: UInt16(kVK_ANSI_J),
            flags: .control
        )
        guard RimeKeyMapper.map(control)?.modifierMask == RimeKeyMapper.ModifierMask.control else {
            throw RimeBridgeError.smokeAssertion("A Control shortcut was not routed to Rime.")
        }

        let option = try requireEvent(
            character: "n",
            keyCode: UInt16(kVK_ANSI_N),
            flags: .option
        )
        guard RimeKeyMapper.map(option)?.modifierMask == RimeKeyMapper.ModifierMask.option else {
            throw RimeBridgeError.smokeAssertion("An Option key was not offered to Rime.")
        }
    }

    private static func verifyModifierMapping() throws {
        let press = RimeKeyMapper.mapModifierChange(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: .shift,
            changedFlags: .shift
        )
        let release = RimeKeyMapper.mapModifierChange(
            keyCode: 0,
            modifierFlags: [],
            changedFlags: .shift
        )
        guard press == RimeMappedKey(
            keyCode: 0xFFE1,
            modifierMask: RimeKeyMapper.ModifierMask.shift
        ), release == RimeMappedKey(
            keyCode: 0xFFE1,
            modifierMask: RimeKeyMapper.ModifierMask.release
        )
        else {
            throw RimeBridgeError.smokeAssertion("Shift press/release mapping is incorrect.")
        }
    }

    private static func verifyInputModeIndicatorTransition() throws {
        guard InputModeIndicatorTransition.state(before: false, after: true) == .english,
            InputModeIndicatorTransition.state(before: true, after: false) == .chinese,
            InputModeIndicatorTransition.state(before: false, after: false) == nil,
            InputModeIndicatorState.chinese.displayText == "中",
            InputModeIndicatorState.english.displayText == "英",
            InputModeIndicatorState.chinese.accessibilityText == "中文",
            InputModeIndicatorState.english.accessibilityText == "英文"
        else {
            throw RimeBridgeError.smokeAssertion("Input mode indicator transition is incorrect.")
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
        try tapModifier(UInt16(kVK_Shift), flag: .shift, in: session)
        let switched = try session.readSnapshot()
        guard switched.status.isASCIIMode, switched.commitText == "ni",
            switched.composition == nil
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
        try tapModifier(UInt16(kVK_Shift), flag: .shift, in: session)
        let restored = try session.readSnapshot()
        guard !restored.status.isASCIIMode, restored.commitText == nil else {
            throw RimeBridgeError.smokeAssertion("A second Shift tap did not restore Chinese mode.")
        }

        try tapModifier(UInt16(kVK_RightShift), flag: .shift, in: session)
        guard try session.readSnapshot().status.isASCIIMode == false else {
            throw RimeBridgeError.smokeAssertion("Right Shift should be a no-op like rime-origin.")
        }
    }

    private static func verifyRimeShortcutRouting(root: URL) throws {
        let session = try makeSession(
            root: root.appendingPathComponent("shortcuts", isDirectory: true),
            schemaIdentifier: "flypy"
        )
        let punctuationBefore = session.option("ascii_punct")
        try routeShortcut(
            character: ".",
            keyCode: UInt16(kVK_ANSI_Period),
            flags: .control,
            in: session
        )
        guard let punctuationBefore,
            session.option("ascii_punct") == !punctuationBefore
        else {
            throw RimeBridgeError.smokeAssertion("Control+. did not toggle Chinese/English punctuation.")
        }

        let simplificationBefore = session.option("simplification")
        try routeShortcut(
            character: "j",
            keyCode: UInt16(kVK_ANSI_J),
            flags: .control,
            in: session
        )
        guard let simplificationBefore,
            session.option("simplification") == !simplificationBefore
        else {
            throw RimeBridgeError.smokeAssertion("Control+j did not toggle character conversion.")
        }

        let fullShapeBefore = session.option("full_shape")
        try routeShortcut(character: " ", keyCode: UInt16(kVK_Space), flags: .shift, in: session)
        guard let fullShapeBefore,
            session.option("full_shape") == !fullShapeBefore
        else {
            throw RimeBridgeError.smokeAssertion("Shift+Space did not toggle full-width mode.")
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

    private static func makeSession(
        root: URL,
        schemaIdentifier: String = "luna_pinyin"
    ) throws -> RimeSession {
        let paths = try RimeServicePaths.applicationDefaults()
        let service = try RimeService(paths: .temporary(root: root, sharedData: paths.sharedData))
        try service.deploy(fullCheck: true)
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schemaIdentifier) else {
            throw RimeBridgeError.smokeAssertion("M3 could not select schema \(schemaIdentifier)")
        }
        return session
    }

    private static func process(
        character: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags = [],
        in session: RimeSession
    ) throws {
        let event = try requireEvent(character: character, keyCode: keyCode, flags: flags)
        guard let mapped = RimeKeyMapper.map(event) else {
            throw RimeBridgeError.smokeAssertion("A test key could not be mapped.")
        }
        guard session.process(keyCode: mapped.keyCode, modifierMask: mapped.modifierMask) else {
            throw RimeBridgeError.smokeAssertion("librime rejected a mapped test key.")
        }
    }

    private static func tapModifier(
        _ keyCode: UInt16,
        flag: NSEvent.ModifierFlags,
        in session: RimeSession
    ) throws {
        guard let press = RimeKeyMapper.mapModifierChange(
            keyCode: keyCode,
            modifierFlags: flag,
            changedFlags: flag
        ), let release = RimeKeyMapper.mapModifierChange(
            keyCode: keyCode,
            modifierFlags: [],
            changedFlags: flag
        ) else {
            throw RimeBridgeError.smokeAssertion("A modifier event could not be mapped.")
        }
        _ = session.process(keyCode: press.keyCode, modifierMask: press.modifierMask)
        _ = session.process(keyCode: release.keyCode, modifierMask: release.modifierMask)
    }

    private static func routeShortcut(
        character: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        in session: RimeSession
    ) throws {
        let event = try requireEvent(character: character, keyCode: keyCode, flags: flags)
        guard let mapped = RimeKeyMapper.map(event) else {
            throw RimeBridgeError.smokeAssertion("A Rime shortcut could not be mapped.")
        }
        _ = session.process(keyCode: mapped.keyCode, modifierMask: mapped.modifierMask)
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

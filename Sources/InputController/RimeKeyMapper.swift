import AppKit
import Carbon

struct ShiftTapTracker {
    private static let shiftKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
    ]

    private var pressedShiftKeys = Set<UInt16>()
    private var eligibleKeyCode: UInt16?

    mutating func update(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard Self.shiftKeyCodes.contains(keyCode) else {
            if !modifierFlags.intersection([.command, .control, .option, .function]).isEmpty {
                eligibleKeyCode = nil
            }
            return false
        }

        if pressedShiftKeys.contains(keyCode) {
            pressedShiftKeys.remove(keyCode)
            let shouldToggle = eligibleKeyCode == keyCode && pressedShiftKeys.isEmpty
            eligibleKeyCode = nil
            return shouldToggle
        }

        pressedShiftKeys.insert(keyCode)
        let hasConflictingModifier = !modifierFlags
            .intersection([.command, .control, .option, .function])
            .isEmpty
        eligibleKeyCode = pressedShiftKeys.count == 1 && !hasConflictingModifier
            ? keyCode
            : nil
        return false
    }

    mutating func noteKeyDown() {
        guard !pressedShiftKeys.isEmpty else {
            return
        }
        eligibleKeyCode = nil
    }

    mutating func reset() {
        pressedShiftKeys.removeAll()
        eligibleKeyCode = nil
    }
}

struct RimeMappedKey: Equatable {
    let keyCode: Int32
    let modifierMask: Int32
}

enum RimeKeyMapper {
    private enum ModifierMask {
        static let shift: Int32 = 1 << 0
        static let capsLock: Int32 = 1 << 1
    }

    private enum KeySymbol {
        static let backspace: Int32 = 0xFF08
        static let tab: Int32 = 0xFF09
        static let `return`: Int32 = 0xFF0D
        static let escape: Int32 = 0xFF1B
        static let home: Int32 = 0xFF50
        static let left: Int32 = 0xFF51
        static let up: Int32 = 0xFF52
        static let right: Int32 = 0xFF53
        static let down: Int32 = 0xFF54
        static let pageUp: Int32 = 0xFF55
        static let pageDown: Int32 = 0xFF56
        static let end: Int32 = 0xFF57
        static let delete: Int32 = 0xFFFF
    }

    private static let specialKeys: [UInt16: Int32] = [
        UInt16(kVK_Delete): KeySymbol.backspace,
        UInt16(kVK_Tab): KeySymbol.tab,
        UInt16(kVK_Return): KeySymbol.return,
        UInt16(kVK_ANSI_KeypadEnter): KeySymbol.return,
        UInt16(kVK_Escape): KeySymbol.escape,
        UInt16(kVK_Home): KeySymbol.home,
        UInt16(kVK_LeftArrow): KeySymbol.left,
        UInt16(kVK_UpArrow): KeySymbol.up,
        UInt16(kVK_RightArrow): KeySymbol.right,
        UInt16(kVK_DownArrow): KeySymbol.down,
        UInt16(kVK_PageUp): KeySymbol.pageUp,
        UInt16(kVK_PageDown): KeySymbol.pageDown,
        UInt16(kVK_End): KeySymbol.end,
        UInt16(kVK_ForwardDelete): KeySymbol.delete,
        UInt16(kVK_Space): 0x20,
    ]

    static func map(_ event: NSEvent) -> RimeMappedKey? {
        guard event.type == .keyDown else {
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.intersection([.command, .control, .option]).isEmpty {
            return nil
        }

        var modifierMask: Int32 = 0
        if flags.contains(.shift) {
            modifierMask |= ModifierMask.shift
        }
        if flags.contains(.capsLock) {
            modifierMask |= ModifierMask.capsLock
        }

        if let specialKey = specialKeys[event.keyCode] {
            return RimeMappedKey(keyCode: specialKey, modifierMask: modifierMask)
        }

        guard
            let characters = event.charactersIgnoringModifiers,
            characters.unicodeScalars.count == 1,
            let scalar = characters.unicodeScalars.first,
            scalar.value >= 0x20,
            scalar.value <= 0x7E
        else {
            return nil
        }

        var keyCode = Int32(scalar.value)
        if keyCode >= 0x61, keyCode <= 0x7A,
            flags.contains(.shift) != flags.contains(.capsLock)
        {
            keyCode -= 0x20
        }
        return RimeMappedKey(keyCode: keyCode, modifierMask: modifierMask)
    }
}

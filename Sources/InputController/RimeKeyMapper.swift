import AppKit
import Carbon

struct RimeMappedKey: Equatable {
    let keyCode: Int32
    let modifierMask: Int32
}

enum RimeKeyMapper {
    enum ModifierMask {
        static let shift: Int32 = 1 << 0
        static let capsLock: Int32 = 1 << 1
        static let control: Int32 = 1 << 2
        static let option: Int32 = 1 << 3
        static let release: Int32 = 1 << 30
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
        static let shiftLeft: Int32 = 0xFFE1
        static let shiftRight: Int32 = 0xFFE2
        static let controlLeft: Int32 = 0xFFE3
        static let controlRight: Int32 = 0xFFE4
        static let capsLock: Int32 = 0xFFE5
        static let optionLeft: Int32 = 0xFFE9
        static let optionRight: Int32 = 0xFFEA
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
        if flags.contains(.command) {
            return nil
        }

        let modifierMask = modifierMask(for: flags)

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

    static func mapModifierChange(
        keyCode eventKeyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        changedFlags: NSEvent.ModifierFlags
    ) -> RimeMappedKey? {
        let descriptor = modifierDescriptor(for: eventKeyCode)
            ?? inferredModifierDescriptor(from: changedFlags)
        guard let descriptor else {
            return nil
        }

        var mask = modifierMask(for: modifierFlags)
        if descriptor.flag == .capsLock {
            mask ^= ModifierMask.capsLock
        } else if !modifierFlags.contains(descriptor.flag) {
            mask |= ModifierMask.release
        }
        return RimeMappedKey(keyCode: descriptor.symbol, modifierMask: mask)
    }

    static func modifierMask(for flags: NSEvent.ModifierFlags) -> Int32 {
        var mask: Int32 = 0
        if flags.contains(.shift) {
            mask |= ModifierMask.shift
        }
        if flags.contains(.capsLock) {
            mask |= ModifierMask.capsLock
        }
        if flags.contains(.control) {
            mask |= ModifierMask.control
        }
        if flags.contains(.option) {
            mask |= ModifierMask.option
        }
        return mask
    }

    private static func modifierDescriptor(
        for keyCode: UInt16
    ) -> (flag: NSEvent.ModifierFlags, symbol: Int32)? {
        switch Int(keyCode) {
        case kVK_Shift: (.shift, KeySymbol.shiftLeft)
        case kVK_RightShift: (.shift, KeySymbol.shiftRight)
        case kVK_Control: (.control, KeySymbol.controlLeft)
        case kVK_RightControl: (.control, KeySymbol.controlRight)
        case kVK_Option: (.option, KeySymbol.optionLeft)
        case kVK_RightOption: (.option, KeySymbol.optionRight)
        case kVK_CapsLock: (.capsLock, KeySymbol.capsLock)
        default: nil
        }
    }

    private static func inferredModifierDescriptor(
        from changes: NSEvent.ModifierFlags
    ) -> (flag: NSEvent.ModifierFlags, symbol: Int32)? {
        if changes.contains(.capsLock) {
            return (.capsLock, KeySymbol.capsLock)
        }
        if changes.contains(.shift) {
            return (.shift, KeySymbol.shiftLeft)
        }
        if changes.contains(.control) {
            return (.control, KeySymbol.controlLeft)
        }
        if changes.contains(.option) {
            return (.option, KeySymbol.optionLeft)
        }
        return nil
    }
}

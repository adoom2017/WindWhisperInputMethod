import Carbon
import Foundation

struct InputSourceState {
    let identifier: String
    let isEnabled: Bool
    let isSelected: Bool
    let isSelectCapable: Bool
}

final class InputSourceManager {
    private let inputSourceIdentifier: String

    init(inputModeIdentifier: String = InputSourceMetadata.inputModeIdentifier) {
        inputSourceIdentifier = inputModeIdentifier
    }

    func registerCurrentBundle() -> OSStatus {
        TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    }

    func state() -> InputSourceState? {
        guard let source = findInputSource() else {
            return nil
        }

        return InputSourceState(
            identifier: inputSourceIdentifier,
            isEnabled: boolProperty(source, key: kTISPropertyInputSourceIsEnabled) ?? false,
            isSelected: boolProperty(source, key: kTISPropertyInputSourceIsSelected) ?? false,
            isSelectCapable: boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable) ?? false
        )
    }

    func enable() -> OSStatus? {
        guard let source = findInputSource() else {
            return nil
        }
        return TISEnableInputSource(source)
    }

    func disable() -> OSStatus? {
        guard let source = findInputSource() else {
            return nil
        }
        return TISDisableInputSource(source)
    }

    func select() -> OSStatus? {
        guard let source = findInputSource() else {
            return nil
        }
        return TISSelectInputSource(source)
    }

    static func currentInputSourceIdentifier() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return stringProperty(source, key: kTISPropertyInputSourceID)
    }

    private func findInputSource() -> TISInputSource? {
        let sourceList = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        for source in sourceList {
            if Self.stringProperty(source, key: kTISPropertyInputSourceID) == inputSourceIdentifier {
                return source
            }
        }
        return nil
    }

    private func boolProperty(_ source: TISInputSource, key: CFString) -> Bool? {
        guard let property = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let property = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
}

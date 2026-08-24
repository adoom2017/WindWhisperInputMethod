#!/usr/bin/env swift

import AppKit
import Foundation

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
window.contentView = textView
window.makeKeyAndOrderFront(nil)
application.activate()
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

let keystrokes: [(String, UInt16)] = [("a", 0), ("b", 11), ("c", 8)]
var handledByInputContext: [Bool] = []

for (character, keyCode) in keystrokes {
    guard let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: keyCode
    ) else {
        fputs("failed to create key event\n", stderr)
        exit(EXIT_FAILURE)
    }

    let handled = textView.inputContext?.handleEvent(event) ?? false
    handledByInputContext.append(handled)
    if !handled {
        textView.keyDown(with: event)
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}

print("text=\(textView.string)")
print("handled=\(handledByInputContext.map(String.init).joined(separator: ","))")
window.close()

guard textView.string == "abc" else {
    exit(EXIT_FAILURE)
}

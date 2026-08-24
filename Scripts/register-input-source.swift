#!/usr/bin/env swift

import Carbon
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: register-input-source.swift /path/to/InputMethod.app\n", stderr)
    exit(EXIT_FAILURE)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let status = TISRegisterInputSource(url as CFURL)
print("status=\(status)")
exit(status == noErr ? EXIT_SUCCESS : EXIT_FAILURE)

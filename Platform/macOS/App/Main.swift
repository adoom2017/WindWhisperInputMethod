import AppKit
import Foundation
import InputMethodKit

@main
enum WindWhisperApplication {
    static func main() {
        if let exitCode = MaintenanceCommand.runIfRequested(arguments: CommandLine.arguments) {
            exit(exitCode)
        }

        NativeRuntime.shared.start()

        guard
            let bundleIdentifier = Bundle.main.bundleIdentifier,
            let connectionName = Bundle.main.object(
                forInfoDictionaryKey: InputSourceMetadata.connectionNameKey
            ) as? String,
            !connectionName.isEmpty
        else {
            fputs("windwhisper: invalid input method metadata\n", stderr)
            exit(EXIT_FAILURE)
        }

        guard let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) else {
            fputs("windwhisper: unable to start InputMethodKit server\n", stderr)
            exit(EXIT_FAILURE)
        }

        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()

        withExtendedLifetime(server) {}
        withExtendedLifetime(delegate) {}
    }
}

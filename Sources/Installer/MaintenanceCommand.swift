import Foundation

enum MaintenanceCommand {
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard let command = arguments.dropFirst().first else {
            return nil
        }

        guard command.hasPrefix("--") else {
            return nil
        }

        switch command {
        case "--register-input-source":
            return registerInputSource()
        case "--enable-input-source":
            return updateInputSource(action: "enable") { $0.enable() }
        case "--enable-input-method-parent":
            return updateInputSource(
                action: "enable parent",
                manager: InputSourceManager(inputModeIdentifier: InputSourceMetadata.bundleIdentifier)
            ) { $0.enable() }
        case "--disable-input-source":
            return updateInputSource(action: "disable") { $0.disable() }
        case "--disable-input-method-parent":
            return updateInputSource(
                action: "disable parent",
                manager: InputSourceManager(inputModeIdentifier: InputSourceMetadata.bundleIdentifier)
            ) { $0.disable() }
        case "--select-input-source":
            return updateInputSource(action: "select") { $0.select() }
        case "--select-input-source-id":
            guard arguments.count == 3 else {
                fputs("RimeInputMethod: --select-input-source-id requires one identifier\n", stderr)
                return EXIT_FAILURE
            }
            return updateInputSource(
                action: "select \(arguments[2])",
                manager: InputSourceManager(inputModeIdentifier: arguments[2])
            ) { $0.select() }
        case "--input-source-status":
            printInputSourceStatus()
            return EXIT_SUCCESS
        case "--input-method-parent-status":
            printInputSourceStatus(
                manager: InputSourceManager(inputModeIdentifier: InputSourceMetadata.bundleIdentifier)
            )
            return EXIT_SUCCESS
        case "--current-input-source":
            print(InputSourceManager.currentInputSourceIdentifier() ?? "<missing>")
            return EXIT_SUCCESS
        case "--diagnose":
            printDiagnostics()
            return EXIT_SUCCESS
        case "--rime-smoke":
            return RimeSmokeTest.run(arguments: arguments)
        case "--m3-smoke":
            return M3SmokeTest.run()
        case "--help":
            printHelp()
            return EXIT_SUCCESS
        default:
            fputs("RimeInputMethod: unknown command: \(command)\n", stderr)
            printHelp()
            return EXIT_FAILURE
        }
    }

    private static func registerInputSource() -> Int32 {
        let status = InputSourceManager().registerCurrentBundle()
        guard status == noErr else {
            fputs("RimeInputMethod: TISRegisterInputSource failed (status \(status))\n", stderr)
            return EXIT_FAILURE
        }

        print("Registered input source: \(InputSourceMetadata.inputModeIdentifier)")
        return EXIT_SUCCESS
    }

    private static func updateInputSource(
        action: String,
        manager: InputSourceManager = InputSourceManager(),
        operation: (InputSourceManager) -> OSStatus?
    ) -> Int32 {
        guard let status = operation(manager) else {
            fputs("RimeInputMethod: input source not found\n", stderr)
            return EXIT_FAILURE
        }
        guard status == noErr else {
            fputs("RimeInputMethod: \(action) failed (status \(status))\n", stderr)
            return EXIT_FAILURE
        }
        print("Input source action succeeded: \(action)")
        return EXIT_SUCCESS
    }

    private static func printInputSourceStatus(manager: InputSourceManager = InputSourceManager()) {
        guard let state = manager.state() else {
            print("found=false")
            return
        }
        print("found=true")
        print("identifier=\(state.identifier)")
        print("enabled=\(state.isEnabled)")
        print("selected=\(state.isSelected)")
        print("selectCapable=\(state.isSelectCapable)")
    }

    private static func printDiagnostics() {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "<missing>"
        let connectionName =
            bundle.object(
                forInfoDictionaryKey: InputSourceMetadata.connectionNameKey
            ) as? String ?? "<missing>"

        print("bundleIdentifier=\(bundleIdentifier)")
        print("bundlePath=\(bundle.bundlePath)")
        print("connectionName=\(connectionName)")
        print("inputModeIdentifier=\(InputSourceMetadata.inputModeIdentifier)")
        print("executableArchitecture=\(executableArchitecture)")
    }

    private static var executableArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }

    private static func printHelp() {
        print(
            """
            Usage: RimeInputMethod [command]

              --register-input-source  Register this installed bundle with macOS
              --enable-input-source    Enable the Simplified Chinese input mode
              --enable-input-method-parent Enable the parent input method
              --disable-input-source   Disable the Simplified Chinese input mode
              --disable-input-method-parent Disable the parent input method
              --select-input-source    Select the Simplified Chinese input mode
              --select-input-source-id Select an enabled input source by identifier
              --input-source-status    Print registration and selection state
              --input-method-parent-status Print parent registration state
              --current-input-source   Print the current keyboard input source ID
              --diagnose               Print non-sensitive bundle diagnostics
              --rime-smoke             Run the isolated librime M2 integration test
              --m3-smoke               Run the M3 key mapping and composition test
              --help                   Show this help
            """
        )
    }
}

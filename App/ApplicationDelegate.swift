import AppKit
import OSLog

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? InputSourceMetadata.bundleIdentifier,
        category: "Lifecycle"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Input method process started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeRuntime.shared.stop()
        logger.notice("Input method process is stopping")
    }
}

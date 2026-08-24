import Foundation
import OSLog

final class RimeRuntime: @unchecked Sendable {
    static let shared = RimeRuntime()

    private let stateLock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? InputSourceMetadata.bundleIdentifier,
        category: "RimeRuntime"
    )
    private var service: RimeService?
    private var startupAttempted = false
    private var startupErrorDescription: String?

    private init() {}

    @discardableResult
    func start() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        if service != nil {
            return true
        }
        if startupAttempted {
            return false
        }
        startupAttempted = true

        do {
            let service = try RimeService(paths: .applicationDefaults())
            try service.deploy(fullCheck: false)
            self.service = service
            logger.notice("librime service is ready")
            return true
        } catch {
            startupErrorDescription = error.localizedDescription
            logger.error("librime startup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func makeSession() throws -> RimeSession {
        guard start() else {
            throw RimeBridgeError.bridge(
                code: -1,
                message: startupErrorDescription ?? "librime service could not be started."
            )
        }

        stateLock.lock()
        let service = self.service
        stateLock.unlock()
        guard let service else {
            throw RimeBridgeError.bridge(code: -1, message: "librime service is unavailable.")
        }
        return try service.makeSession()
    }

    func stop() {
        stateLock.lock()
        service = nil
        stateLock.unlock()
        logger.notice("librime service stopped")
    }
}

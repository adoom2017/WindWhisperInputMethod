import Foundation
import OSLog

struct RimeRuntimeDiagnosticStatus: Sendable {
    let isReady: Bool
    let version: String
    let lastError: String?
    let userDataDirectoryExists: Bool
    let logDirectoryExists: Bool
}

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
            logger.notice("native input engine is ready")
            return true
        } catch {
            startupErrorDescription = error.localizedDescription
            logger.error("native input engine startup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func makeSession() throws -> RimeSession {
        guard start() else {
            throw RimeBridgeError.bridge(
                code: -1,
                message: startupErrorDescription ?? "The input engine could not be started."
            )
        }

        stateLock.lock()
        let service = self.service
        stateLock.unlock()
        guard let service else {
            throw RimeBridgeError.bridge(code: -1, message: "The input engine is unavailable.")
        }
        let session = try service.makeSession()
        try FengYuSettingsStore.shared.snapshot.apply(to: session)
        return session
    }

    func redeploy(fullCheck: Bool = true) throws {
        guard start() else {
            throw RimeBridgeError.bridge(
                code: -1,
                message: startupErrorDescription ?? "The input engine could not be started."
            )
        }
        stateLock.lock()
        let service = self.service
        stateLock.unlock()
        guard let service else {
            throw RimeBridgeError.bridge(code: -1, message: "The input engine is unavailable.")
        }
        try service.deploy(fullCheck: fullCheck)
    }

    func diagnosticStatus() -> RimeRuntimeDiagnosticStatus {
        stateLock.lock()
        let service = self.service
        let lastError = startupErrorDescription
        stateLock.unlock()

        let fileManager = FileManager.default
        return RimeRuntimeDiagnosticStatus(
            isReady: service != nil,
            version: service?.version ?? "unknown",
            lastError: lastError,
            userDataDirectoryExists: service.map {
                fileManager.fileExists(atPath: $0.paths.userData.path)
            } ?? false,
            logDirectoryExists: service.map {
                fileManager.fileExists(atPath: $0.paths.logs.path)
            } ?? false
        )
    }

    func stop() {
        stateLock.lock()
        service = nil
        stateLock.unlock()
        logger.notice("native input engine stopped")
    }
}

import Foundation
import OSLog

struct NativeRuntimeDiagnosticStatus: Sendable {
    let isReady: Bool
    let version: String
    let lastError: String?
    let userDataDirectoryExists: Bool
    let logDirectoryExists: Bool
}

final class NativeRuntime: @unchecked Sendable {
    static let shared = NativeRuntime()

    private let stateLock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? InputSourceMetadata.bundleIdentifier,
        category: "NativeRuntime"
    )
    private var service: InputService?
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
            let service = try InputService(paths: .applicationDefaults())
            self.service = service
            logger.notice("windwhisper input engine is ready")
            return true
        } catch {
            startupErrorDescription = error.localizedDescription
            logger.error("windwhisper input engine startup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func makeSession() throws -> InputSession {
        guard start() else {
            throw InputEngineError.runtime(
                code: -1,
                message: startupErrorDescription ?? "The input engine could not be started."
            )
        }

        stateLock.lock()
        let service = self.service
        stateLock.unlock()
        guard let service else {
            throw InputEngineError.runtime(code: -1, message: "The input engine is unavailable.")
        }
        let session = try service.makeSession()
        try FengYuSettingsStore.shared.snapshot.apply(to: session)
        return session
    }

    func refreshConfiguration(paths requestedPaths: InputServicePaths? = nil) throws {
        stateLock.lock()
        let currentPaths = service?.paths
        stateLock.unlock()

        let paths = try requestedPaths ?? currentPaths ?? .applicationDefaults()
        let refreshedService = try InputService(paths: paths)

        stateLock.lock()
        service = refreshedService
        startupAttempted = true
        startupErrorDescription = nil
        stateLock.unlock()
        logger.notice("windwhisper configuration refreshed")
    }

    func diagnosticStatus() -> NativeRuntimeDiagnosticStatus {
        stateLock.lock()
        let service = self.service
        let lastError = startupErrorDescription
        stateLock.unlock()

        let fileManager = FileManager.default
        return NativeRuntimeDiagnosticStatus(
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
        logger.notice("windwhisper input engine stopped")
    }
}

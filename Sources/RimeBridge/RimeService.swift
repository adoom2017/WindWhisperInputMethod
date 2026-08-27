import Foundation

enum RimeBridgeError: Error, LocalizedError {
    case missingBundledData
    case invalidCString
    case bridge(code: Int32, message: String)
    case invalidUTF8Offset
    case smokeAssertion(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledData:
            "The bundled input-engine data directory is missing."
        case .invalidCString:
            "An input-engine path could not be represented as UTF-8."
        case .bridge(let code, _):
            "Input engine error \(code)."
        case .invalidUTF8Offset:
            "The input engine returned an invalid composition offset."
        case .smokeAssertion(let message):
            "Input-engine smoke test failed: \(message)"
        }
    }
}

struct RimeServicePaths: Sendable {
    let sharedData: URL
    let userData: URL
    let prebuiltData: URL
    let staging: URL
    let logs: URL
    let legacyUserData: [URL]

    static func applicationDefaults(bundle: Bundle = .main) throws -> Self {
        guard let resources = bundle.resourceURL else {
            throw RimeBridgeError.missingBundledData
        }
        let sharedData = resources.appendingPathComponent("Rime", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sharedData.path) else {
            throw RimeBridgeError.missingBundledData
        }

        // Keep the existing local dictionary, deployment and log directories when
        // the bundle identity changes to repair a corrupted macOS input-source record.
        let identifier = InputSourceMetadata.persistentDataIdentifier
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        let applicationSupport =
            library
            .appendingPathComponent("Application Support", isDirectory: true)
        let userData =
            applicationSupport
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        let legacyUserData = InputSourceMetadata.legacyPersistentDataIdentifiers.map { identifier in
            applicationSupport
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("Rime", isDirectory: true)
        }
        return Self(
            sharedData: sharedData,
            userData: userData,
            prebuiltData: sharedData.appendingPathComponent("build", isDirectory: true),
            staging: userData.appendingPathComponent("build", isDirectory: true),
            logs:
                library
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true),
            legacyUserData: legacyUserData
        )
    }

    static func temporary(
        root: URL,
        sharedData: URL,
        legacyUserData: [URL] = []
    ) -> Self {
        let userData = root.appendingPathComponent("user", isDirectory: true)
        return Self(
            sharedData: sharedData,
            userData: userData,
            prebuiltData: sharedData.appendingPathComponent("build", isDirectory: true),
            staging: userData.appendingPathComponent("build", isDirectory: true),
            logs: root.appendingPathComponent("logs", isDirectory: true),
            legacyUserData: legacyUserData
        )
    }
}

private final class CStringStorage {
    private(set) var values: [UnsafeMutablePointer<CChar>]

    init(_ strings: [String]) throws {
        values = try strings.map { string in
            guard let value = strdup(string) else {
                throw RimeBridgeError.invalidCString
            }
            return value
        }
    }

    deinit {
        for value in values {
            free(value)
        }
    }
}

final class RimeService: @unchecked Sendable {
    private var handle: RBServiceRef?
    private let engineLock = NSRecursiveLock()

    let paths: RimeServicePaths
    let version: String

    init(paths: RimeServicePaths, minLogLevel: Int32 = 2) throws {
        self.paths = paths
        let fileManager = FileManager.default
        try Self.migrateLegacyUserDataIfNeeded(at: paths, using: fileManager)
        try fileManager.createDirectory(at: paths.userData, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.staging, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        try Self.seedBundledFlypyUserTables(at: paths, using: fileManager)

        let strings = try CStringStorage([
            paths.sharedData.path,
            paths.userData.path,
            paths.prebuiltData.path,
            paths.staging.path,
            paths.logs.path,
            "windwhisper",
            "windwhisper",
            "0.2.0",
            "windwhisper.input_method",
        ])
        var configuration = RBServiceConfiguration(
            shared_data_dir: UnsafePointer(strings.values[0]),
            user_data_dir: UnsafePointer(strings.values[1]),
            prebuilt_data_dir: UnsafePointer(strings.values[2]),
            staging_dir: UnsafePointer(strings.values[3]),
            log_dir: UnsafePointer(strings.values[4]),
            distribution_name: UnsafePointer(strings.values[5]),
            distribution_code_name: UnsafePointer(strings.values[6]),
            distribution_version: UnsafePointer(strings.values[7]),
            app_name: UnsafePointer(strings.values[8]),
            min_log_level: minLogLevel
        )

        var createdHandle: RBServiceRef?
        try Self.check(rb_service_create(&configuration, &createdHandle, nil))
        guard let createdHandle else {
            throw RimeBridgeError.bridge(code: -1, message: "Missing service handle.")
        }
        handle = createdHandle
        version = rb_service_version(createdHandle).map(String.init(cString:)) ?? "unknown"
    }

    private static func migrateLegacyUserDataIfNeeded(
        at paths: RimeServicePaths,
        using fileManager: FileManager
    ) throws {
        guard !fileManager.fileExists(atPath: paths.userData.path) else {
            return
        }
        guard let source = paths.legacyUserData.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else {
            return
        }

        try fileManager.createDirectory(
            at: paths.userData.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: source, to: paths.userData)
    }

    deinit {
        withEngineLock {
            if let handle {
                rb_service_destroy(handle)
            }
        }
    }

    func deploy(fullCheck: Bool) throws {
        guard let handle else {
            throw RimeBridgeError.bridge(code: -1, message: "Service is not active.")
        }
        try withEngineLock {
            try Self.withBridgeError { error in
                rb_service_deploy(handle, fullCheck ? 1 : 0, error)
            }
        }
    }

    private static func seedBundledFlypyUserTables(
        at paths: RimeServicePaths,
        using fileManager: FileManager
    ) throws {
        for name in ["flypy_top", "flypy_sys", "flypy_user", "flypy_full", "flypy_ok"] {
            let fileName = "\(name).txt"
            let source = paths.sharedData.appendingPathComponent(fileName)
            let destination = paths.userData.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: source.path),
                !fileManager.fileExists(atPath: destination.path)
            else {
                continue
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func makeSession() throws -> RimeSession {
        guard let handle else {
            throw RimeBridgeError.bridge(code: -1, message: "Service is not active.")
        }
        return try withEngineLock {
            var session: RBSessionRef = 0
            try Self.withBridgeError { error in
                rb_session_create(handle, &session, error)
            }
            return RimeSession(service: self, serviceHandle: handle, sessionHandle: session)
        }
    }

    fileprivate func withEngineLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        engineLock.lock()
        defer { engineLock.unlock() }
        return try operation()
    }

    fileprivate static func check(_ result: RBResult) throws {
        guard result != RB_RESULT_OK else {
            return
        }
        throw RimeBridgeError.bridge(
            code: Int32(result.rawValue),
            message: "Unspecified bridge failure."
        )
    }

    fileprivate static func withBridgeError(
        _ operation: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> RBResult
    ) throws {
        var messagePointer: UnsafeMutablePointer<CChar>?
        let result = operation(&messagePointer)
        defer {
            if let messagePointer {
                rb_error_message_free(messagePointer)
            }
        }
        guard result != RB_RESULT_OK else {
            return
        }
        let message =
            messagePointer.map { String(cString: UnsafePointer($0)) }
            ?? "Unspecified bridge failure."
        throw RimeBridgeError.bridge(code: Int32(result.rawValue), message: message)
    }
}

final class RimeSession: @unchecked Sendable {
    private let service: RimeService
    private let serviceHandle: RBServiceRef
    private var sessionHandle: RBSessionRef

    fileprivate init(
        service: RimeService,
        serviceHandle: RBServiceRef,
        sessionHandle: RBSessionRef
    ) {
        self.service = service
        self.serviceHandle = serviceHandle
        self.sessionHandle = sessionHandle
    }

    deinit {
        service.withEngineLock {
            if sessionHandle != 0 {
                rb_session_destroy(serviceHandle, sessionHandle)
            }
        }
    }

    @discardableResult
    func process(keyCode: Int32, modifierMask: Int32 = 0) -> Bool {
        service.withEngineLock {
            rb_session_process_key(serviceHandle, sessionHandle, keyCode, modifierMask) != 0
        }
    }

    @discardableResult
    func simulate(sequence: String) -> Bool {
        service.withEngineLock {
            sequence.withCString {
                rb_session_simulate_key_sequence(serviceHandle, sessionHandle, $0) != 0
            }
        }
    }

    @discardableResult
    func commitComposition() -> Bool {
        service.withEngineLock {
            rb_session_commit_composition(serviceHandle, sessionHandle) != 0
        }
    }

    func clearComposition() {
        service.withEngineLock {
            rb_session_clear_composition(serviceHandle, sessionHandle)
        }
    }

    @discardableResult
    func selectSchema(identifier: String) -> Bool {
        service.withEngineLock {
            identifier.withCString {
                rb_session_select_schema(serviceHandle, sessionHandle, $0) != 0
            }
        }
    }

    @discardableResult
    func setOption(_ name: String, enabled: Bool) -> Bool {
        service.withEngineLock {
            name.withCString {
                rb_session_set_option(serviceHandle, sessionHandle, $0, enabled ? 1 : 0) != 0
            }
        }
    }

    func option(_ name: String) -> Bool? {
        service.withEngineLock {
            var value: Int32 = 0
            let available = name.withCString {
                rb_session_get_option(serviceHandle, sessionHandle, $0, &value) != 0
            }
            return available ? value != 0 : nil
        }
    }

    @discardableResult
    func selectCandidate(at index: Int) -> Bool {
        guard index >= 0 else {
            return false
        }
        return service.withEngineLock {
            rb_session_select_candidate(serviceHandle, sessionHandle, index) != 0
        }
    }

    func readSnapshot() throws -> RimeSnapshot {
        try service.withEngineLock {
            var bridgeSnapshot = RBSnapshot()
            rb_snapshot_init(&bridgeSnapshot)
            defer { rb_snapshot_clear(&bridgeSnapshot) }

            try RimeService.withBridgeError { error in
                rb_session_read_snapshot(serviceHandle, sessionHandle, &bridgeSnapshot, error)
            }

            let preedit = bridgeSnapshot.preedit.map { String(cString: UnsafePointer($0)) } ?? ""
            let composition: RimeCompositionSnapshot?
            if preedit.isEmpty {
                composition = nil
            } else {
                guard
                    let range = RimeRangeConverter.utf16Range(
                        startUTF8Offset: Int(bridgeSnapshot.selection_start),
                        endUTF8Offset: Int(bridgeSnapshot.selection_end),
                        in: preedit
                    ),
                    let cursor = RimeRangeConverter.utf16Offset(
                        forUTF8Offset: Int(bridgeSnapshot.cursor_pos),
                        in: preedit
                    )
                else {
                    throw RimeBridgeError.invalidUTF8Offset
                }
                composition = RimeCompositionSnapshot(
                    text: preedit,
                    selectionRange: range,
                    cursorPosition: cursor
                )
            }

            let candidates: [RimeCandidateSnapshot]
            if let pointer = bridgeSnapshot.candidates {
                candidates = (0..<Int(truncatingIfNeeded: bridgeSnapshot.candidate_count)).map { index in
                    let candidate = pointer[index]
                    return RimeCandidateSnapshot(
                        text: candidate.text.map { String(cString: UnsafePointer($0)) } ?? "",
                        comment: candidate.comment.map { String(cString: UnsafePointer($0)) }
                    )
                }
            } else {
                candidates = []
            }

            return RimeSnapshot(
                commitText: bridgeSnapshot.commit_text.map { String(cString: UnsafePointer($0)) },
                composition: composition,
                menu: RimeMenuSnapshot(
                    pageSize: Int(bridgeSnapshot.page_size),
                    pageNumber: Int(bridgeSnapshot.page_number),
                    isLastPage: bridgeSnapshot.is_last_page != 0,
                    highlightedIndex: Int(bridgeSnapshot.highlighted_candidate_index),
                    candidates: candidates
                ),
                status: RimeStatusSnapshot(
                    schemaIdentifier: bridgeSnapshot.schema_id.map { String(cString: UnsafePointer($0)) },
                    schemaName: bridgeSnapshot.schema_name.map { String(cString: UnsafePointer($0)) },
                    isComposing: bridgeSnapshot.is_composing != 0,
                    isASCIIMode: bridgeSnapshot.is_ascii_mode != 0,
                    isDisabled: bridgeSnapshot.is_disabled != 0
                )
            )
        }
    }
}

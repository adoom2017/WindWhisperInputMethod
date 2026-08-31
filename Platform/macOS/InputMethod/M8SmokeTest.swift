import AppKit
import Foundation

enum M8SmokeTest {
    private struct Measurements {
        let engineInitializationMilliseconds: Double
        let configurationRefreshMilliseconds: Double
        let keyLatency: Percentiles
        let candidateLayoutLatency: Percentiles
        let stressIterations: Int
        let residentMemoryGrowthBytes: Int64
    }

    private struct Percentiles {
        let p50: Double
        let p95: Double
        let p99: Double
    }

    @MainActor
    static func run(arguments: [String]) -> Int32 {
        do {
            let measurements = try execute(arguments: arguments)
            print("unicodeRanges=passed")
            print("candidateUpdateInvalidation=passed")
            print("shortcutPassthrough=passed")
            print("singleCommitDelivery=passed")
            print("sessionLifecycle=passed")
            print("snapshotAllocationBalance=passed")
            print("engineInitializationMs=\(format(measurements.engineInitializationMilliseconds))")
            print("configurationRefreshMs=\(format(measurements.configurationRefreshMilliseconds))")
            print("keyLatencyP50Ms=\(format(measurements.keyLatency.p50))")
            print("keyLatencyP95Ms=\(format(measurements.keyLatency.p95))")
            print("keyLatencyP99Ms=\(format(measurements.keyLatency.p99))")
            print("candidateLayoutP50Ms=\(format(measurements.candidateLayoutLatency.p50))")
            print("candidateLayoutP95Ms=\(format(measurements.candidateLayoutLatency.p95))")
            print("candidateLayoutP99Ms=\(format(measurements.candidateLayoutLatency.p99))")
            print("stressIterations=\(measurements.stressIterations)")
            print("residentMemoryGrowthBytes=\(measurements.residentMemoryGrowthBytes)")
            return EXIT_SUCCESS
        } catch {
            fputs("windwhisper M8: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    @MainActor
    private static func execute(arguments: [String]) throws -> Measurements {
        try verifyUnicodeRanges()
        try verifyCandidateUpdateInvalidation()
        try verifyShortcutPassthrough()

        guard let resources = Bundle.main.resourceURL else {
            throw InputEngineError.missingBundledData
        }
        let sharedData = resources
        let explicitRoot = argumentValue(after: "--user-data-root", in: arguments)
        let root = explicitRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("windwhisper-M8-\(UUID().uuidString)", isDirectory: true)
        let shouldRemoveRoot = explicitRoot == nil
        let stressSeconds = max(
            argumentValue(after: "--stress-seconds", in: arguments).flatMap(Double.init) ?? 10,
            1
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if shouldRemoveRoot {
                try? FileManager.default.removeItem(at: root)
            }
        }

        let paths = InputServicePaths.temporary(root: root, sharedData: sharedData)
        var service: InputService!
        let initialization = try measure {
            service = try InputService(paths: paths, minLogLevel: 2)
        }
        let configurationRefresh = try measure {
            service = try InputService(paths: paths, minLogLevel: 2)
        }

        try verifySingleCommitDelivery(service: service)
        let performance = try measureInputPath(service: service)
        let beforeStress = try requireDiagnostics(service)
        let stressIterations = try stressSessions(service: service, seconds: stressSeconds)
        let afterStress = try requireDiagnostics(service)

        guard afterStress.activeSessionCount == 0 else {
            throw InputEngineError.smokeAssertion(
                "session churn left \(afterStress.activeSessionCount) active sessions"
            )
        }
        guard afterStress.snapshotAllocationCount == 0 else {
            throw InputEngineError.smokeAssertion(
                "snapshot churn left \(afterStress.snapshotAllocationCount) runtime allocations"
            )
        }
        guard performance.key.p95 < 16 else {
            throw InputEngineError.smokeAssertion(
                "ordinary key P95 was \(format(performance.key.p95)) ms (limit 16 ms)"
            )
        }

        return Measurements(
            engineInitializationMilliseconds: initialization,
            configurationRefreshMilliseconds: configurationRefresh,
            keyLatency: performance.key,
            candidateLayoutLatency: performance.layout,
            stressIterations: stressIterations,
            residentMemoryGrowthBytes: Int64(afterStress.residentMemoryBytes)
                - Int64(beforeStress.residentMemoryBytes)
        )
    }

    private static func verifyUnicodeRanges() throws {
        let fixtures: [(String, Int, Int)] = [
            ("ASCII", 5, 5),
            ("a😀中", 5, 3),
            ("e\u{301}", 3, 2),
            ("𠀀A", 4, 2),
        ]
        for (text, utf8Offset, expectedUTF16Offset) in fixtures {
            guard RangeConverter.utf16Offset(
                forUTF8Offset: utf8Offset,
                in: text
            ) == expectedUTF16Offset else {
                throw InputEngineError.smokeAssertion("Unicode range fixture failed")
            }
        }
        guard
            RangeConverter.utf16Range(
                startUTF8Offset: 1,
                endUTF8Offset: 5,
                in: "a😀中"
            ) == NSRange(location: 1, length: 2),
            RangeConverter.utf16Offset(forUTF8Offset: 2, in: "a😀中") == nil,
            RangeConverter.utf16Range(
                startUTF8Offset: 5,
                endUTF8Offset: 1,
                in: "a😀中"
            ) == nil
        else {
            throw InputEngineError.smokeAssertion("invalid Unicode boundaries were accepted")
        }
    }

    private static func verifyCandidateUpdateInvalidation() throws {
        let gate = CandidateWindowUpdateGate()
        let first = gate.beginUpdate()
        let second = gate.beginUpdate()
        guard !gate.isCurrent(first), gate.isCurrent(second) else {
            throw InputEngineError.smokeAssertion("a stale candidate update remained current")
        }
        let hide = gate.invalidate()
        guard !gate.isCurrent(second), gate.isCurrent(hide) else {
            throw InputEngineError.smokeAssertion("candidate hide did not invalidate pending UI work")
        }
        let third = gate.beginUpdate()
        guard !gate.isCurrent(hide), gate.isCurrent(third) else {
            throw InputEngineError.smokeAssertion("a stale hide superseded a newer candidate update")
        }
    }

    private static func verifyShortcutPassthrough() throws {
        guard let commandEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ), KeyMapper.map(commandEvent) == nil else {
            throw InputEngineError.smokeAssertion("Command shortcut was consumed")
        }
    }

    private static func verifySingleCommitDelivery(service: InputService) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.fullPinyin.rawValue),
            session.simulate(sequence: "nihao ")
        else {
            throw InputEngineError.smokeAssertion("commit fixture was not consumed")
        }
        let client = M3InputClientDouble()
        _ = ClientUpdater.apply(
            try session.readSnapshot(),
            to: client,
            hadMarkedText: false
        )
        _ = ClientUpdater.apply(
            try session.readSnapshot(),
            to: client,
            hadMarkedText: false
        )
        guard client.committedText == "你好" else {
            throw InputEngineError.smokeAssertion("one engine commit was not delivered exactly once")
        }
    }

    @MainActor
    private static func measureInputPath(
        service: InputService
    ) throws -> (key: Percentiles, layout: Percentiles) {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue) else {
            throw InputEngineError.smokeAssertion("performance schema could not be selected")
        }
        let theme = CandidateWindowTheme.system(
            environment: CandidateAccessibilityEnvironment(
                reduceTransparency: false,
                increaseContrast: false,
                reduceMotion: true
            )
        )
        for _ in 0..<50 {
            _ = session.process(keyCode: 0x6E)
            _ = try session.readSnapshot()
            session.clearComposition()
        }

        var keySamples = [Double]()
        var layoutSamples = [Double]()
        keySamples.reserveCapacity(2_000)
        layoutSamples.reserveCapacity(2_000)
        for index in 0..<2_000 {
            let keyCode: Int32 = index.isMultiple(of: 2) ? 0x6E : 0x69
            let started = DispatchTime.now().uptimeNanoseconds
            guard session.process(keyCode: keyCode) else {
                throw InputEngineError.smokeAssertion("performance key was not consumed")
            }
            let snapshot = try session.readSnapshot()
            let layoutStarted = DispatchTime.now().uptimeNanoseconds
            if !snapshot.menu.candidates.isEmpty {
                let model = CandidateWindowModel(menu: snapshot.menu)
                _ = CandidateHorizontalLayout.make(model: model, theme: theme)
            }
            let finished = DispatchTime.now().uptimeNanoseconds
            keySamples.append(milliseconds(from: started, to: finished))
            layoutSamples.append(milliseconds(from: layoutStarted, to: finished))
            if !index.isMultiple(of: 2) {
                session.clearComposition()
            }
        }
        return (percentiles(keySamples), percentiles(layoutSamples))
    }

    private static func stressSessions(service: InputService, seconds: Double) throws -> Int {
        let deadline = Date().addingTimeInterval(seconds)
        var iterations = 0
        while Date() < deadline {
            try autoreleasepool {
                let session = try service.makeSession()
                guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue),
                    session.simulate(sequence: "nihc")
                else {
                    throw InputEngineError.smokeAssertion("stress input was not consumed")
                }
                for _ in 0..<8 {
                    _ = try session.readSnapshot()
                }
                session.clearComposition()
            }
            iterations += 1
        }
        return iterations
    }

    private static func requireDiagnostics(_ service: InputService) throws -> InputEngineDiagnostics {
        guard let diagnostics = service.diagnostics() else {
            throw InputEngineError.smokeAssertion("runtime diagnostics were unavailable")
        }
        return diagnostics
    }

    private static func measure(_ operation: () throws -> Void) rethrows -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        try operation()
        return milliseconds(from: started, to: DispatchTime.now().uptimeNanoseconds)
    }

    private static func percentiles(_ values: [Double]) -> Percentiles {
        let sorted = values.sorted()
        func value(at percentile: Double) -> Double {
            let index = min(Int(Double(sorted.count - 1) * percentile), sorted.count - 1)
            return sorted[index]
        }
        return Percentiles(p50: value(at: 0.50), p95: value(at: 0.95), p99: value(at: 0.99))
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

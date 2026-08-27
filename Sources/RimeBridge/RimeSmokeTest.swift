import Foundation

enum RimeSmokeTest {
    static func run(arguments: [String]) -> Int32 {
        do {
            try execute(arguments: arguments)
            print("engineVersion=native-1.0")
            print("fullPinyin=passed")
            print("flypyPhonetic=passed")
            print("flypyShape=passed")
            print("flypyFourKeyAutoCommit=passed")
            print("flypyFourKeyMultipleCandidates=passed")
            print("customWords=passed")
            print("librimeDependency=absent")
            return EXIT_SUCCESS
        } catch {
            fputs("windwhisper native engine: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func execute(arguments: [String]) throws {
        try verifyUnicodeRangeConversion()
        guard let resources = Bundle.main.resourceURL else {
            throw RimeBridgeError.missingBundledData
        }
        let sharedData = resources.appendingPathComponent("Rime", isDirectory: true)
        let explicitRoot = argumentValue(after: "--user-data-root", in: arguments)
        let root = explicitRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("windwhisper-native-\(UUID().uuidString)", isDirectory: true)
        let shouldRemoveRoot = explicitRoot == nil
        let paths = RimeServicePaths.temporary(root: root, sharedData: sharedData)
        try FileManager.default.createDirectory(at: paths.userData, withIntermediateDirectories: true)
        try "风语输入法\tfy\t9999999\n".write(
            to: paths.userData.appendingPathComponent("custom_words.tsv"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            if shouldRemoveRoot { try? FileManager.default.removeItem(at: root) }
        }

        let service = try RimeService(paths: paths)
        guard service.version == "native-1.0" else {
            throw RimeBridgeError.smokeAssertion("unexpected native engine version")
        }
        try verifyCandidate(service: service, schema: .fullPinyin, code: "nihao", text: "你好")
        try verifyCandidate(service: service, schema: .flypyPhonetic, code: "nihc", text: "你好")
        try verifyCandidate(service: service, schema: .flypy, code: "ubu", text: "是不是")
        try verifyFirstCandidate(service: service, schema: .flypy, code: "iys", text: "纯")
        try verifyOrderedCandidates(
            service: service,
            schema: .flypy,
            code: "ufme",
            expected: ["什么", "𬳽"]
        )
        try verifyCandidate(service: service, schema: .flypy, code: "fy", text: "风语输入法")

        let shape = try service.makeSession()
        guard shape.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            shape.simulate(sequence: "nirx"),
            try shape.readSnapshot().commitText == "你"
        else {
            throw RimeBridgeError.smokeAssertion("four-key Flypy auto commit failed")
        }

        let frameworks = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let bundledLibrime = frameworks.appendingPathComponent("librime.1.dylib")
        guard !FileManager.default.fileExists(atPath: bundledLibrime.path) else {
            throw RimeBridgeError.smokeAssertion("librime is still bundled")
        }
    }

    private static func verifyCandidate(
        service: RimeService,
        schema: FengYuSchema,
        code: String,
        text: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schema.rawValue), session.simulate(sequence: code) else {
            throw RimeBridgeError.smokeAssertion("\(schema.displayName) did not consume \(code)")
        }
        let snapshot = try session.readSnapshot()
        guard let index = snapshot.menu.candidates.firstIndex(where: { $0.text == text }) else {
            throw RimeBridgeError.smokeAssertion("\(schema.displayName) did not produce \(text)")
        }
        guard session.selectCandidate(at: index), try session.readSnapshot().commitText == text else {
            throw RimeBridgeError.smokeAssertion("\(schema.displayName) did not commit \(text)")
        }
    }

    private static func verifyFirstCandidate(
        service: RimeService,
        schema: FengYuSchema,
        code: String,
        text: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schema.rawValue), session.simulate(sequence: code) else {
            throw RimeBridgeError.smokeAssertion("\(schema.displayName) did not consume \(code)")
        }
        let snapshot = try session.readSnapshot()
        guard snapshot.menu.candidates.first?.text == text else {
            throw RimeBridgeError.smokeAssertion("\(schema.displayName) did not prioritize \(text) for \(code)")
        }
    }

    private static func verifyOrderedCandidates(
        service: RimeService,
        schema: FengYuSchema,
        code: String,
        expected: [String]
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schema.rawValue), session.simulate(sequence: code) else {
            throw RimeBridgeError.smokeAssertion("\(schema.displayName) did not consume \(code)")
        }
        let snapshot = try session.readSnapshot()
        let actual = snapshot.menu.candidates.prefix(expected.count).map(\.text)
        guard snapshot.commitText == nil, snapshot.composition?.text == code,
            Array(actual) == expected
        else {
            throw RimeBridgeError.smokeAssertion(
                "\(schema.displayName) candidate order for \(code) was \(actual)"
            )
        }
    }

    private static func verifyUnicodeRangeConversion() throws {
        let text = "a😀中"
        guard
            RimeRangeConverter.utf16Range(
                startUTF8Offset: 1,
                endUTF8Offset: 5,
                in: text
            ) == NSRange(location: 1, length: 2),
            RimeRangeConverter.utf16Offset(forUTF8Offset: 8, in: text) == 4
        else {
            throw RimeBridgeError.smokeAssertion("UTF-8 to UTF-16 conversion failed")
        }
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }
}

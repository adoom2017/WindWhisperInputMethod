import Foundation

enum RimeSmokeTest {
    static func run(arguments: [String]) -> Int32 {
        do {
            let result = try execute(arguments: arguments)
            print("librimeVersion=\(result.version)")
            print("schemaLoaded=\(result.schemaLoaded)")
            print("candidateCountPositive=\(result.candidateCount > 0)")
            print("expectedCandidateFound=\(result.expectedCandidateFound)")
            print("commitMatched=\(result.commitMatched)")
            print("rangeConversion=passed")
            print("sessionLifecycle=passed")
            return EXIT_SUCCESS
        } catch {
            fputs("windwhisper: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private struct Result {
        let version: String
        let schemaLoaded: Bool
        let candidateCount: Int
        let expectedCandidateFound: Bool
        let commitMatched: Bool
    }

    private static func execute(arguments: [String]) throws -> Result {
        try verifyUnicodeRangeConversion()

        guard let resources = Bundle.main.resourceURL else {
            throw RimeBridgeError.missingBundledData
        }
        let sharedData = resources.appendingPathComponent("Rime", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sharedData.path) else {
            throw RimeBridgeError.missingBundledData
        }

        let explicitRoot = argumentValue(after: "--user-data-root", in: arguments)
        let temporaryRoot: URL
        let shouldRemoveRoot: Bool
        if let explicitRoot {
            temporaryRoot = URL(fileURLWithPath: explicitRoot, isDirectory: true)
            shouldRemoveRoot = false
        } else {
            temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("windwhisper-M2-\(UUID().uuidString)", isDirectory: true)
            shouldRemoveRoot = true
        }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            if shouldRemoveRoot {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
        }

        let service = try RimeService(
            paths: .temporary(root: temporaryRoot, sharedData: sharedData),
            minLogLevel: 2
        )
        guard service.version == "1.16.0" else {
            throw RimeBridgeError.smokeAssertion("unexpected librime version")
        }
        try service.deploy(fullCheck: true)

        let session = try service.makeSession()
        guard session.selectSchema(identifier: "luna_pinyin") else {
            throw RimeBridgeError.smokeAssertion("full pinyin schema could not be selected")
        }
        guard session.simulate(sequence: "nihao") else {
            throw RimeBridgeError.smokeAssertion("key sequence was not consumed")
        }
        let candidateSnapshot = try session.readSnapshot()
        let expectedIndex = candidateSnapshot.menu.candidates.firstIndex { $0.text == "你好" }
        guard let expectedIndex else {
            throw RimeBridgeError.smokeAssertion("expected candidate was not generated")
        }
        guard session.selectCandidate(at: expectedIndex) else {
            throw RimeBridgeError.smokeAssertion("candidate selection failed")
        }
        let commitSnapshot = try session.readSnapshot()
        guard commitSnapshot.commitText == "你好" else {
            throw RimeBridgeError.smokeAssertion("selected candidate was not committed")
        }

        return Result(
            version: service.version,
            schemaLoaded: candidateSnapshot.status.schemaIdentifier == "luna_pinyin",
            candidateCount: candidateSnapshot.menu.candidates.count,
            expectedCandidateFound: true,
            commitMatched: true
        )
    }

    private static func verifyUnicodeRangeConversion() throws {
        let text = "a😀中"
        guard
            RimeRangeConverter.utf16Range(
                startUTF8Offset: 1,
                endUTF8Offset: 5,
                in: text
            ) == NSRange(location: 1, length: 2),
            RimeRangeConverter.utf16Offset(forUTF8Offset: 8, in: text) == 4,
            RimeRangeConverter.utf16Offset(forUTF8Offset: 2, in: text) == nil
        else {
            throw RimeBridgeError.smokeAssertion("UTF-8 to UTF-16 range conversion failed")
        }
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

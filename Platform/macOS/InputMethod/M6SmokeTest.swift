import Foundation

enum M6SmokeTest {
    private struct SchemeCase {
        let identifier: String
        let name: String
        let sequence: String
        let expected: String
    }

    private static let schemes = [
        SchemeCase(identifier: FengYuSchema.flypy.rawValue, name: "小鹤音形", sequence: "ni", expected: "你"),
        SchemeCase(identifier: FengYuSchema.fullPinyin.rawValue, name: "风语全拼", sequence: "nihao", expected: "你好"),
        SchemeCase(identifier: FengYuSchema.flypyPhonetic.rawValue, name: "小鹤双拼", sequence: "nihc", expected: "你好"),
    ]

    private static let flypyPrimaryShortcuts: [(code: String, text: String)] = [
        ("w", "我"), ("d", "的"), ("u", "是"),
    ]

    static func run(arguments: [String]) -> Int32 {
        do {
            let result = try execute(arguments: arguments)
            print("schemaCorpusPassed=\(result.schemeCount)")
            print("defaultSchema=flypyShape")
            print("flypyAuxiliaryCode=passed")
            print("flypyRecoveredDictionary=passed")
            print("flypyPrimaryShortcutOrder=passed")
            print("flypyShortCodes=passed")
            print("flypyCompatibilityPhrases=passed")
            print("flypyFourCharacterPhrases=passed")
            print("auxiliaryBroadCandidates=\(result.broadCandidateCount)")
            print("auxiliaryNarrowCandidates=\(result.narrowCandidateCount)")
            print("auxiliaryExpectedCandidate=passed")
            print("userOverridePreserved=passed")
            print("userDictionaryPreserved=passed")
            return EXIT_SUCCESS
        } catch {
            fputs("windwhisper M6: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private struct Result {
        let schemeCount: Int
        let broadCandidateCount: Int
        let narrowCandidateCount: Int
    }

    private static func execute(arguments: [String]) throws -> Result {
        guard let resources = Bundle.main.resourceURL else {
            throw InputEngineError.missingBundledData
        }
        let sharedData = resources
        try validateBundledData(at: sharedData)

        let explicitRoot = argumentValue(after: "--user-data-root", in: arguments)
        let root = explicitRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("windwhisper-M6-\(UUID().uuidString)", isDirectory: true)
        let shouldRemoveRoot = explicitRoot == nil
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if shouldRemoveRoot {
                try? FileManager.default.removeItem(at: root)
            }
        }

        let paths = InputServicePaths.temporary(root: root, sharedData: sharedData)
        let customURL = paths.userData.appendingPathComponent("custom_words.tsv")
        let customContents = "# 词条<Tab>编码<Tab>可选权重\n风语测试\tfycs\t9999999\n"
        try FileManager.default.createDirectory(at: paths.userData, withIntermediateDirectories: true)
        try customContents.write(to: customURL, atomically: true, encoding: .utf8)

        var broadCandidateCount = 0
        var narrowCandidateCount = 0
        do {
            let service = try InputService(paths: paths, minLogLevel: 2)

            let defaultSession = try service.makeSession()
            let defaultSnapshot = try defaultSession.readSnapshot()
            guard defaultSnapshot.status.schemaIdentifier == FengYuSchema.flypy.rawValue,
                defaultSnapshot.status.schemaName == "小鹤音形"
            else {
                throw InputEngineError.smokeAssertion("small crane auxiliary-code schema is not the default")
            }

            for scheme in schemes {
                let session = try service.makeSession()
                guard session.selectSchema(identifier: scheme.identifier) else {
                    throw InputEngineError.smokeAssertion("could not select \(scheme.identifier)")
                }
                guard session.simulate(sequence: scheme.sequence) else {
                    throw InputEngineError.smokeAssertion("\(scheme.identifier) did not consume its corpus")
                }
                let snapshot = try session.readSnapshot()
                guard snapshot.status.schemaIdentifier == scheme.identifier else {
                    throw InputEngineError.smokeAssertion("\(scheme.identifier) status mismatch")
                }
                guard snapshot.status.schemaName == scheme.name else {
                    throw InputEngineError.smokeAssertion("\(scheme.identifier) display name mismatch")
                }
                guard snapshot.menu.candidates.contains(where: { $0.text == scheme.expected }) else {
                    let candidates = snapshot.menu.candidates.map(\.text).joined(separator: ",")
                    throw InputEngineError.smokeAssertion(
                        "\(scheme.identifier) corpus candidate missing "
                            + "(sequence=\(scheme.sequence), expected=\(scheme.expected), candidates=\(candidates))"
                    )
                }
            }

            let missingSession = try service.makeSession()
            let missingIdentifier = "fengyu_schema_that_does_not_exist"
            guard !missingSession.selectSchema(identifier: missingIdentifier) else {
                throw InputEngineError.smokeAssertion("a missing schema was accepted")
            }
            let missingSnapshot = try missingSession.readSnapshot()
            guard missingSnapshot.status.schemaIdentifier != missingIdentifier else {
                throw InputEngineError.smokeAssertion("a missing schema became active")
            }

            let flypyAuxiliarySession = try service.makeSession()
            guard flypyAuxiliarySession.selectSchema(identifier: FengYuSchema.flypy.rawValue),
                flypyAuxiliarySession.simulate(sequence: "ni")
            else {
                throw InputEngineError.smokeAssertion("could not start small crane auxiliary input")
            }
            let flypyBroad = try flypyAuxiliarySession.readSnapshot()
            flypyAuxiliarySession.clearComposition()
            guard flypyAuxiliarySession.simulate(sequence: "nir") else {
                throw InputEngineError.smokeAssertion("small crane auxiliary code was not consumed")
            }
            let flypyNarrow = try flypyAuxiliarySession.readSnapshot()
            guard flypyBroad.menu.candidates.first?.text == "你",
                flypyNarrow.menu.candidates.first?.text == "倪"
            else {
                throw InputEngineError.smokeAssertion(
                    "small crane shape code mismatch "
                        + "(broad=\(flypyBroad.menu.candidates.map(\.text).joined(separator: ",")), "
                        + "narrow=\(flypyNarrow.menu.candidates.map(\.text).joined(separator: ",")))"
                )
            }
            guard flypyAuxiliarySession.simulate(sequence: "x"),
                try flypyAuxiliarySession.readSnapshot().commitText == "你"
            else {
                throw InputEngineError.smokeAssertion("the full small crane code nirx did not commit 你")
            }

            try verifyFlypyCandidate(service: service, sequence: "k", expected: "可以")
            try verifyFlypyCandidate(service: service, sequence: "aj", expected: "按键")
            try verifyFlypyCandidate(service: service, sequence: "hvy", expected: "呼之欲出")
            for shortcut in flypyPrimaryShortcuts {
                try verifyFlypyFirstCandidate(
                    service: service,
                    sequence: shortcut.code,
                    expected: shortcut.text
                )
            }
            try verifyFlypyCandidateOrder(service: service, sequence: "w", expectedPrefix: ["我", "位"])
            try verifyFlypyCandidateOrder(service: service, sequence: "d", expectedPrefix: ["的", "打"])
            try verifyFlypyCandidateOrder(service: service, sequence: "u", expectedPrefix: ["是", "时"])
            try verifyFlypyCompatibilityOutput(service: service, sequence: "ubu", expected: "是不是")
            try verifyFlypyCompatibilityOutput(service: service, sequence: "hdui", expected: "还是")
            try verifyFlypyCompatibilityOutput(service: service, sequence: "biru", expected: "比如")
            try verifyFlypyAutoCommit(service: service, sequence: "dsdk", expected: "洞")
            try verifyFlypyCompatibilityOutput(service: service, sequence: "ahqi", expected: "昂起")
            try verifyFlypyCompatibilityOutput(service: service, sequence: "anui", expected: "按时")
            try verifyFlypyCompatibilityOutput(service: service, sequence: "keyi", expected: "可以")
            try verifyFlypyCompatibilityOutput(service: service, sequence: "quts", expected: "趋同")

            let auxiliarySession = try service.makeSession()
            guard auxiliarySession.selectSchema(identifier: FengYuSchema.fullPinyin.rawValue) else {
                throw InputEngineError.smokeAssertion("could not select full pinyin for auxiliary test")
            }
            guard auxiliarySession.simulate(sequence: ";zuo") else {
                throw InputEngineError.smokeAssertion("auxiliary prefix was not consumed")
            }
            let broadSnapshot = try auxiliarySession.readSnapshot()
            broadCandidateCount = broadSnapshot.menu.candidates.count
            guard broadSnapshot.menu.candidates.contains(where: { !($0.comment ?? "").isEmpty }) else {
                throw InputEngineError.smokeAssertion("auxiliary comments were not displayed")
            }
            auxiliarySession.clearComposition()
            guard auxiliarySession.simulate(sequence: ";zuok") else {
                throw InputEngineError.smokeAssertion("auxiliary stem was not consumed")
            }
            let narrowed = try auxiliarySession.readSnapshot()
            narrowCandidateCount = narrowed.menu.candidates.count
            guard narrowed.menu.candidates.contains(where: { $0.text == "左" }) else {
                throw InputEngineError.smokeAssertion("auxiliary expected candidate was missing")
            }
            guard broadCandidateCount > narrowCandidateCount, narrowCandidateCount > 0 else {
                throw InputEngineError.smokeAssertion("auxiliary code did not narrow candidates")
            }

            auxiliarySession.clearComposition()
            let flypySession = try service.makeSession()
            guard flypySession.selectSchema(identifier: FengYuSchema.flypyPhonetic.rawValue),
                flypySession.simulate(sequence: "nihc")
            else {
                throw InputEngineError.smokeAssertion("pure double pinyin regressed after auxiliary input")
            }
            let pureSnapshot = try flypySession.readSnapshot()
            guard pureSnapshot.menu.candidates.contains(where: { $0.text == "你好" }) else {
                throw InputEngineError.smokeAssertion("pure double pinyin candidate changed")
            }
            guard let expectedIndex = pureSnapshot.menu.candidates.firstIndex(where: { $0.text == "你好" }),
                flypySession.selectCandidate(at: expectedIndex)
            else {
                throw InputEngineError.smokeAssertion("could not train the user dictionary")
            }
        }

        guard try String(contentsOf: customURL, encoding: .utf8) == customContents else {
            throw InputEngineError.smokeAssertion("input engine overwrote custom_words.tsv")
        }
        let userDictionary = paths.userData.appendingPathComponent("custom_words.tsv")
        guard FileManager.default.fileExists(atPath: userDictionary.path) else {
            throw InputEngineError.smokeAssertion("custom dictionary was not persisted")
        }

        return Result(
            schemeCount: schemes.count,
            broadCandidateCount: broadCandidateCount,
            narrowCandidateCount: narrowCandidateCount
        )
    }

    private static func verifyFlypyCandidate(
        service: InputService,
        sequence: String,
        expected: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue), session.simulate(sequence: sequence) else {
            throw InputEngineError.smokeAssertion("Flypy did not consume short code \(sequence)")
        }
        let snapshot = try session.readSnapshot()
        guard snapshot.menu.candidates.contains(where: { $0.text == expected }) else {
            throw InputEngineError.smokeAssertion(
                "Flypy short code \(sequence) is missing candidate \(expected)"
            )
        }
    }

    private static func verifyFlypyAutoCommit(
        service: InputService,
        sequence: String,
        expected: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue), session.simulate(sequence: sequence) else {
            throw InputEngineError.smokeAssertion("Flypy did not consume phrase code \(sequence)")
        }
        let snapshot = try session.readSnapshot()
        guard snapshot.commitText == expected else {
            let candidates = snapshot.menu.candidates.map(\.text).joined(separator: ",")
            throw InputEngineError.smokeAssertion(
                "Flypy phrase code \(sequence) did not commit \(expected) "
                    + "(commit=\(snapshot.commitText ?? "<none>"), candidates=\(candidates))"
            )
        }
    }

    private static func verifyFlypyFirstCandidate(
        service: InputService,
        sequence: String,
        expected: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue), session.simulate(sequence: sequence) else {
            throw InputEngineError.smokeAssertion("Flypy did not consume primary shortcut \(sequence)")
        }
        let snapshot = try session.readSnapshot()
        guard snapshot.menu.candidates.first?.text == expected else {
            let candidates = snapshot.menu.candidates.map(\.text).joined(separator: ",")
            throw InputEngineError.smokeAssertion(
                "Flypy primary shortcut \(sequence) did not rank \(expected) first "
                    + "(candidates=\(candidates))"
            )
        }
    }

    private static func verifyFlypyCandidateOrder(
        service: InputService,
        sequence: String,
        expectedPrefix: [String]
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue), session.simulate(sequence: sequence) else {
            throw InputEngineError.smokeAssertion("Flypy did not consume ordered shortcut \(sequence)")
        }
        let candidates = try session.readSnapshot().menu.candidates.map(\.text)
        guard Array(candidates.prefix(expectedPrefix.count)) == expectedPrefix else {
            throw InputEngineError.smokeAssertion(
                "Flypy shortcut \(sequence) order mismatch "
                    + "(expected=\(expectedPrefix.joined(separator: ",")), "
                    + "candidates=\(candidates.joined(separator: ",")))"
            )
        }
    }

    private static func verifyFlypyCompatibilityOutput(
        service: InputService,
        sequence: String,
        expected: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue), session.simulate(sequence: sequence) else {
            throw InputEngineError.smokeAssertion("Flypy did not consume compatibility code \(sequence)")
        }
        let snapshot = try session.readSnapshot()
        guard snapshot.commitText == expected || snapshot.menu.candidates.first?.text == expected else {
            let candidates = snapshot.menu.candidates.map(\.text).joined(separator: ",")
            throw InputEngineError.smokeAssertion(
                "Flypy compatibility code \(sequence) did not output \(expected) "
                    + "(commit=\(snapshot.commitText ?? "<none>"), candidates=\(candidates))"
            )
        }
    }

    private static func validateBundledData(at sharedData: URL) throws {
        let required = ["fy.dict.yaml"]
        for file in required {
            let url = sharedData.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw InputEngineError.smokeAssertion("missing bundled data: \(file)")
            }
        }
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }
}

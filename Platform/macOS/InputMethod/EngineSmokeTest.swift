import Foundation

enum EngineSmokeTest {
    static func run(arguments: [String]) -> Int32 {
        do {
            try execute(arguments: arguments)
            print("engineVersion=native-1.0")
            print("fullPinyin=passed")
            print("flypyPhonetic=passed")
            print("longSentenceInput=passed")
            print("statisticalLanguageModel=passed")
            print("simplifiedTraditionalConversion=passed")
            print("flypyShape=passed")
            print("selectiveSchemaLoading=passed")
            print("flypyFourKeyAutoCommit=passed")
            print("flypyFourKeyMultipleCandidates=passed")
            print("flypyFourKeyContinuationCommit=passed")
            print("candidatePageAliases=passed")
            print("flypyCodeReverseLookup=passed")
            print("customWords=passed")
            print("customWordsRefresh=passed")
            print("customWordsManagement=passed")
            print("failedRefreshPreservesConfiguration=passed")
            print("externalEngineDependency=absent")
            return EXIT_SUCCESS
        } catch {
            fputs("windwhisper native engine: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func execute(arguments: [String]) throws {
        try verifyUnicodeRangeConversion()
        try verifyCustomWordsStore()
        guard let resources = Bundle.main.resourceURL else {
            throw InputEngineError.missingBundledData
        }
        let sharedData = resources
        let explicitRoot = argumentValue(after: "--user-data-root", in: arguments)
        let root = explicitRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("windwhisper-native-\(UUID().uuidString)", isDirectory: true)
        let shouldRemoveRoot = explicitRoot == nil
        let paths = InputServicePaths.temporary(root: root, sharedData: sharedData)
        try FileManager.default.createDirectory(at: paths.userData, withIntermediateDirectories: true)
        try "风语输入法\tfy\t9999999\n".write(
            to: paths.userData.appendingPathComponent("custom_words.tsv"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            if shouldRemoveRoot { try? FileManager.default.removeItem(at: root) }
        }

        let service = try InputService(paths: paths)
        guard service.version == "native-1.0" else {
            throw InputEngineError.smokeAssertion("unexpected native engine version")
        }
        try verifyCandidate(service: service, schema: .fullPinyin, code: "nihao", text: "你好")
        try verifyCandidate(service: service, schema: .flypyPhonetic, code: "nihc", text: "你好")
        try verifyLongSentenceInput(service: service)
        try verifyScriptConversion(service: service)
        try verifyCandidate(service: service, schema: .flypy, code: "ubu", text: "是不是")
        try verifyFirstCandidate(service: service, schema: .flypy, code: "iys", text: "纯")
        try verifyOrderedCandidates(
            service: service,
            schema: .flypy,
            code: "ufme",
            expected: ["什么", "𬳽"]
        )
        try verifyFlypyContinuationCommit(service: service)
        for (code, expected) in [("w", ["我", "位"]), ("d", ["的", "打"]), ("u", ["是", "时"])] {
            try verifyOrderedCandidates(service: service, schema: .flypy, code: code, expected: expected)
        }
        try verifyCandidate(service: service, schema: .flypy, code: "fy", text: "风语输入法")
        try verifyCandidatePageAliases(service: service)
        try verifyFlypyCodeReverseLookup(service: service)
        try verifySelectiveSchemaLoading(paths: paths)

        try "刷新配置\tsx\t9999999\n".write(
            to: paths.userData.appendingPathComponent("custom_words.tsv"),
            atomically: true,
            encoding: .utf8
        )
        try NativeRuntime.shared.refreshConfiguration(paths: paths)
        defer { NativeRuntime.shared.stop() }
        let refreshedSession = try NativeRuntime.shared.makeSession()
        guard refreshedSession.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            refreshedSession.simulate(sequence: "sx"),
            try refreshedSession.readSnapshot().menu.candidates.first?.text == "刷新配置"
        else {
            throw InputEngineError.smokeAssertion("custom words did not take effect after configuration refresh")
        }

        let invalidPaths = InputServicePaths.temporary(
            root: root.appendingPathComponent("invalid-refresh", isDirectory: true),
            sharedData: root.appendingPathComponent("missing-resources", isDirectory: true)
        )
        let failedRefresh = Result { try NativeRuntime.shared.refreshConfiguration(paths: invalidPaths) }
        guard case .failure = failedRefresh else {
            throw InputEngineError.smokeAssertion("configuration refresh accepted missing bundled data")
        }
        let retainedSession = try NativeRuntime.shared.makeSession()
        guard retainedSession.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            retainedSession.simulate(sequence: "sx"),
            try retainedSession.readSnapshot().menu.candidates.first?.text == "刷新配置"
        else {
            throw InputEngineError.smokeAssertion("failed refresh discarded the active configuration")
        }

        let shape = try service.makeSession()
        guard shape.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            shape.simulate(sequence: "nirx"),
            try shape.readSnapshot().commitText == "你"
        else {
            throw InputEngineError.smokeAssertion("four-key Flypy auto commit failed")
        }

    }

    private static func verifySelectiveSchemaLoading(paths: InputServicePaths) throws {
        let fixtures: [(schema: FengYuSchema, code: String, expected: String)] = [
            (.flypy, "ubu", "是不是"),
            (.flypyPhonetic, "nihc", "你好"),
            (.fullPinyin, "nihao", "你好"),
        ]
        for fixture in fixtures {
            let service = try InputService(paths: paths, enabledSchemas: [fixture.schema])
            try verifyCandidate(
                service: service,
                schema: fixture.schema,
                code: fixture.code,
                text: fixture.expected
            )
        }
    }

    private static func verifyCandidatePageAliases(service: InputService) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            session.simulate(sequence: "ni")
        else {
            throw InputEngineError.smokeAssertion("could not prepare candidates for page aliases")
        }
        let firstPage = try session.readSnapshot()
        guard !firstPage.menu.isLastPage,
            session.process(keyCode: 0x3D),
            try session.readSnapshot().menu.pageNumber == 1,
            session.process(keyCode: 0x2D),
            try session.readSnapshot().menu.pageNumber == 0
        else {
            throw InputEngineError.smokeAssertion("-/= did not page through candidates")
        }
    }

    private static func verifyFlypyContinuationCommit(service: InputService) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            session.simulate(sequence: "biru")
        else {
            throw InputEngineError.smokeAssertion("could not prepare ambiguous four-key continuation")
        }
        let before = try session.readSnapshot()
        guard before.menu.candidates.count > 1,
            before.menu.candidates.first?.text == "比如",
            session.process(keyCode: Int32(Character("n").asciiValue!))
        else {
            throw InputEngineError.smokeAssertion("biru did not expose the expected ambiguous candidates")
        }
        let after = try session.readSnapshot()
        guard after.commitText == "比如", after.composition?.text == "n" else {
            throw InputEngineError.smokeAssertion("continuation did not commit the first four-key candidate")
        }
    }

    private static func verifyFlypyCodeReverseLookup(service: InputService) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            session.simulate(sequence: "ni"),
            session.process(keyCode: 0x7E, modifierMask: KeyMapper.ModifierMask.shift)
        else {
            throw InputEngineError.smokeAssertion("could not enter Flypy code reverse lookup")
        }
        let lookup = try session.readSnapshot()
        guard lookup.composition?.text == "ni~",
            lookup.menu.candidates.first?.text == "你",
            lookup.menu.candidates.first?.comment == "nirx",
            session.simulate(sequence: "r")
        else {
            throw InputEngineError.smokeAssertion("Flypy reverse lookup did not expose the full code")
        }
        let narrowed = try session.readSnapshot()
        guard narrowed.composition?.text == "ni~r",
            narrowed.menu.candidates.first?.text == "倪",
            narrowed.menu.candidates.first?.comment == "nire",
            session.process(keyCode: 0xFF08),
            try session.readSnapshot().composition?.text == "ni~",
            session.process(keyCode: 0xFF08),
            try session.readSnapshot().composition?.text == "ni"
        else {
            throw InputEngineError.smokeAssertion("Flypy reverse lookup editing state is inconsistent")
        }

        let commitSession = try service.makeSession()
        guard commitSession.selectSchema(identifier: FengYuSchema.flypy.rawValue),
            commitSession.simulate(sequence: "ni~"),
            commitSession.selectCandidate(at: 0),
            try commitSession.readSnapshot().commitText == "你"
        else {
            throw InputEngineError.smokeAssertion("Flypy reverse lookup committed its annotation")
        }

        let pinyin = try service.makeSession()
        guard pinyin.selectSchema(identifier: FengYuSchema.fullPinyin.rawValue),
            pinyin.simulate(sequence: "ni"),
            !pinyin.process(keyCode: 0x7E, modifierMask: KeyMapper.ModifierMask.shift),
            try pinyin.readSnapshot().composition?.text == "ni"
        else {
            throw InputEngineError.smokeAssertion("reverse lookup leaked into another schema")
        }
    }

    private static func verifyLongSentenceInput(service: InputService) throws {
        let fixtures: [(FengYuSchema, code: String, expected: String)] = [
            (.fullPinyin, "jintiantianqihenhao", "今天天气很好"),
            (.flypyPhonetic, "jbtmtmqihfhc", "今天天气很好"),
            (.fullPinyin, "haishiyiyang", "还是一样"),
            (.flypyPhonetic, "hduiyiyh", "还是一样"),
            (.fullPinyin, "yiqi", "一起"),
            (.fullPinyin, "womenkeyiyiqi", "我们可以一起"),
            (.flypyPhonetic, "womfkeyiyiqi", "我们可以一起"),
            (.fullPinyin, "woxiangyaozhege", "我想要这个"),
            (.flypyPhonetic, "woxlycvege", "我想要这个"),
            (.fullPinyin, "zhegeshijie", "这个世界"),
        ]
        for (schema, code, expectedText) in fixtures {
            let session = try service.makeSession()
            var settings = FengYuSettingsSnapshot.defaults
            settings.schema = schema
            try settings.apply(to: session)
            guard session.simulate(sequence: code) else {
                throw InputEngineError.smokeAssertion("\(schema.displayName) did not consume a long sentence")
            }
            let snapshot = try session.readSnapshot()
            guard snapshot.menu.candidates.first?.text == expectedText,
                session.commitComposition(),
                try session.readSnapshot().commitText == expectedText
            else {
                throw InputEngineError.smokeAssertion(
                    "\(schema.displayName) did not decode \(code): \(snapshot.menu.candidates.map(\.text))"
                )
            }
        }

        let traditionalSession = try service.makeSession()
        var traditionalSettings = FengYuSettingsSnapshot.defaults
        traditionalSettings.schema = .fullPinyin
        traditionalSettings.usesSimplifiedChinese = false
        try traditionalSettings.apply(to: traditionalSession)
        guard traditionalSession.simulate(sequence: "haishiyiyang"),
            try traditionalSession.readSnapshot().menu.candidates.first?.text == "還是一樣",
            traditionalSession.commitComposition(),
            try traditionalSession.readSnapshot().commitText == "還是一樣"
        else {
            throw InputEngineError.smokeAssertion("traditional long sentence conversion was not applied")
        }
    }

    private static func verifyScriptConversion(service: InputService) throws {
        let fixtures: [(FengYuSchema, String)] = [
            (.fullPinyin, "hanzi"),
            (.flypyPhonetic, "hjzi"),
        ]
        for (schema, code) in fixtures {
            for (usesSimplified, expected, rejected) in [
                (true, "汉字", "漢字"),
                (false, "漢字", "汉字"),
            ] {
                let session = try service.makeSession()
                var settings = FengYuSettingsSnapshot.defaults
                settings.schema = schema
                settings.usesSimplifiedChinese = usesSimplified
                try settings.apply(to: session)
                guard session.simulate(sequence: code) else {
                    throw InputEngineError.smokeAssertion("\(schema.displayName) did not consume a script fixture")
                }
                let snapshot = try session.readSnapshot()
                guard snapshot.menu.candidates.first?.text == expected,
                    !snapshot.menu.candidates.contains(where: { $0.text == rejected }),
                    session.commitComposition(),
                    try session.readSnapshot().commitText == expected
                else {
                    throw InputEngineError.smokeAssertion(
                        "\(schema.displayName) did not honor the configured Chinese script"
                    )
                }
            }
        }
    }

    private static func verifyCandidate(
        service: InputService,
        schema: FengYuSchema,
        code: String,
        text: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schema.rawValue), session.simulate(sequence: code) else {
            throw InputEngineError.smokeAssertion("\(schema.displayName) did not consume \(code)")
        }
        let snapshot = try session.readSnapshot()
        guard let index = snapshot.menu.candidates.firstIndex(where: { $0.text == text }) else {
            throw InputEngineError.smokeAssertion("\(schema.displayName) did not produce \(text)")
        }
        guard session.selectCandidate(at: index), try session.readSnapshot().commitText == text else {
            throw InputEngineError.smokeAssertion("\(schema.displayName) did not commit \(text)")
        }
    }

    private static func verifyFirstCandidate(
        service: InputService,
        schema: FengYuSchema,
        code: String,
        text: String
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schema.rawValue), session.simulate(sequence: code) else {
            throw InputEngineError.smokeAssertion("\(schema.displayName) did not consume \(code)")
        }
        let snapshot = try session.readSnapshot()
        guard snapshot.menu.candidates.first?.text == text else {
            throw InputEngineError.smokeAssertion("\(schema.displayName) did not prioritize \(text) for \(code)")
        }
    }

    private static func verifyOrderedCandidates(
        service: InputService,
        schema: FengYuSchema,
        code: String,
        expected: [String]
    ) throws {
        let session = try service.makeSession()
        guard session.selectSchema(identifier: schema.rawValue), session.simulate(sequence: code) else {
            throw InputEngineError.smokeAssertion("\(schema.displayName) did not consume \(code)")
        }
        let snapshot = try session.readSnapshot()
        let actual = snapshot.menu.candidates.prefix(expected.count).map(\.text)
        guard snapshot.commitText == nil, snapshot.composition?.text == code,
            Array(actual) == expected
        else {
            throw InputEngineError.smokeAssertion(
                "\(schema.displayName) candidate order for \(code) was \(actual)"
            )
        }
    }

    private static func verifyUnicodeRangeConversion() throws {
        let text = "a😀中"
        guard
            RangeConverter.utf16Range(
                startUTF8Offset: 1,
                endUTF8Offset: 5,
                in: text
            ) == NSRange(location: 1, length: 2),
            RangeConverter.utf16Offset(forUTF8Offset: 8, in: text) == 4
        else {
            throw InputEngineError.smokeAssertion("UTF-8 to UTF-16 conversion failed")
        }
    }

    private static func verifyCustomWordsStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("windwhisper-custom-words-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("custom_words.tsv")
        let store = CustomWordsStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }

        guard try store.load() == .empty else {
            throw InputEngineError.smokeAssertion("missing custom words file did not load as empty")
        }

        let saved = try store.save(CustomWordsDocument(
            comments: ["# 保留这条注释"],
            entries: [
                CustomWordEntry(text: " 风语 ", code: "FY"),
                CustomWordEntry(text: "输入法", code: "urf", weight: 9_999),
            ]
        ))
        let loaded = try store.load()
        guard
            saved.entries.map(\.text) == ["风语", "输入法"],
            loaded.entries.map(\.code) == ["fy", "urf"],
            loaded.entries.map(\.weight) == [nil, 9_999],
            loaded.comments == ["# 保留这条注释"],
            try CustomWordsStore.contents(for: loaded).contains("输入法\turf\t9999")
        else {
            throw InputEngineError.smokeAssertion("custom words were not normalized and persisted")
        }

        let merged = try CustomWordsStore.merging(
            CustomWordsDocument(comments: ["# 不导入这条注释"], entries: [
                CustomWordEntry(text: "风语", code: "fy"),
                CustomWordEntry(text: "词库导入", code: "ckdr", weight: 8_888),
            ]),
            into: loaded
        )
        guard
            merged.addedEntries.map(\.text) == ["词库导入"],
            merged.skippedCount == 1,
            merged.document.entries.map(\.text) == ["风语", "输入法", "词库导入"],
            merged.document.comments == loaded.comments
        else {
            throw InputEngineError.smokeAssertion("custom words import did not merge and deduplicate")
        }

        let duplicateResult = Swift.Result {
            try store.save(CustomWordsDocument(comments: [], entries: [
                CustomWordEntry(text: "风语", code: "fy"),
                CustomWordEntry(text: "风语", code: "FY"),
            ]))
        }
        guard case .failure = duplicateResult else {
            throw InputEngineError.smokeAssertion("duplicate custom words were accepted")
        }

        let invalidCodeResult = Swift.Result {
            try store.save(CustomWordsDocument(
                comments: [],
                entries: [CustomWordEntry(text: "风语", code: "feng-yu")]
            ))
        }
        let reloaded = try store.load()
        guard
            case .failure = invalidCodeResult,
            reloaded.entries.map(\.text) == loaded.entries.map(\.text),
            reloaded.entries.map(\.code) == loaded.entries.map(\.code),
            reloaded.entries.map(\.weight) == loaded.entries.map(\.weight),
            reloaded.comments == loaded.comments
        else {
            throw InputEngineError.smokeAssertion("invalid custom word changed the persisted file")
        }
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }
}

import Foundation

enum InputEngineError: Error, LocalizedError {
    case missingBundledData
    case runtime(code: Int32, message: String)
    case invalidUTF8Offset
    case smokeAssertion(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledData:
            "The bundled dictionary is missing."
        case .runtime(let code, let message):
            "Input engine error \(code): \(message)"
        case .invalidUTF8Offset:
            "The input engine returned an invalid composition offset."
        case .smokeAssertion(let message):
            "Input-engine smoke test failed: \(message)"
        }
    }
}

struct InputServicePaths: Sendable {
    let sharedData: URL
    let userData: URL
    let logs: URL

    static func applicationDefaults(bundle: Bundle = .main) throws -> Self {
        guard let resources = bundle.resourceURL else {
            throw InputEngineError.missingBundledData
        }
        let sharedData = resources
        let dictionary = sharedData.appendingPathComponent("fy.dict.yaml")
        guard FileManager.default.fileExists(atPath: dictionary.path) else {
            throw InputEngineError.missingBundledData
        }

        let identifier = InputSourceMetadata.persistentDataIdentifier
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        let root = library
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        let userData = root.appendingPathComponent("User", isDirectory: true)
        return Self(
            sharedData: sharedData,
            userData: userData,
            logs: library.appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
        )
    }

    static func temporary(root: URL, sharedData: URL) -> Self {
        let userData = root.appendingPathComponent("User", isDirectory: true)
        return Self(
            sharedData: sharedData,
            userData: userData,
            logs: root.appendingPathComponent("Logs", isDirectory: true)
        )
    }
}

private struct NativeDictionaryEntry: Sendable {
    let text: String
    let code: String
    let weight: Int
    let order: Int
}

private struct NativeSentencePath {
    let text: String
    let unigramScore: Double
    let segmentCount: Int
}

private struct NativeStatisticalLanguageModel {
    struct Builder {
        private var bigramFrequencies = [UInt64: Float]()
        private var trigramFrequencies = [UInt64: Float]()

        mutating func observe(text: String, frequency: Int) {
            let scalars = text.unicodeScalars.map(\.value)
            guard frequency > 0, (2...12).contains(scalars.count) else { return }
            let contribution = Float(log1p(Double(frequency)))
            for index in 1..<scalars.count {
                bigramFrequencies[Self.bigramKey(scalars[index - 1], scalars[index]), default: 0]
                    += contribution
            }
            guard scalars.count >= 3 else { return }
            for index in 2..<scalars.count {
                trigramFrequencies[
                    Self.trigramKey(scalars[index - 2], scalars[index - 1], scalars[index]),
                    default: 0
                ] += contribution
            }
        }

        func build() -> NativeStatisticalLanguageModel {
            NativeStatisticalLanguageModel(
                bigramFrequencies: bigramFrequencies,
                trigramFrequencies: trigramFrequencies
            )
        }

        private static func bigramKey(_ first: UInt32, _ second: UInt32) -> UInt64 {
            UInt64(first) << 21 | UInt64(second)
        }

        private static func trigramKey(_ first: UInt32, _ second: UInt32, _ third: UInt32) -> UInt64 {
            UInt64(first) << 42 | UInt64(second) << 21 | UInt64(third)
        }
    }

    private let bigramFrequencies: [UInt64: Float]
    private let trigramFrequencies: [UInt64: Float]

    func score(text: String) -> Double {
        let scalars = text.unicodeScalars.map(\.value)
        guard scalars.count >= 2 else { return 0 }

        var bigramScore = 0.0
        for index in 1..<scalars.count {
            let key = UInt64(scalars[index - 1]) << 21 | UInt64(scalars[index])
            bigramScore += log1p(Double(bigramFrequencies[key, default: 0]))
        }
        bigramScore /= Double(scalars.count - 1)

        guard scalars.count >= 3 else { return bigramScore }
        var trigramScore = 0.0
        for index in 2..<scalars.count {
            let key = UInt64(scalars[index - 2]) << 42
                | UInt64(scalars[index - 1]) << 21
                | UInt64(scalars[index])
            trigramScore += log1p(Double(trigramFrequencies[key, default: 0]))
        }
        trigramScore /= Double(scalars.count - 2)
        return bigramScore * 0.8 + trigramScore * 1.2
    }

    func score(path: NativeSentencePath) -> Double {
        let characterCount = max(path.text.count, 1)
        let normalizedUnigramScore = path.unigramScore / Double(characterCount)
        return score(text: path.text)
            + normalizedUnigramScore * 0.25
            - Double(path.segmentCount) * 4.0
    }
}

private final class NativeDictionary: @unchecked Sendable {
    private let shapeEntries: [NativeDictionaryEntry]
    private let shapeCodesByText: [String: [String]]
    private let pinyinEntries: [NativeDictionaryEntry]
    private let flypyPhoneticEntries: [NativeDictionaryEntry]
    private let languageModel: NativeStatisticalLanguageModel

    init(sharedData: URL, userData: URL) throws {
        let dictionaryURL = sharedData.appendingPathComponent("fy.dict.yaml")
        guard FileManager.default.fileExists(atPath: dictionaryURL.path) else {
            throw InputEngineError.missingBundledData
        }

        let allEntries = try Self.readConsolidatedEntries(at: dictionaryURL)
        let shape = allEntries.filter { $0.source == .flypy }
        var languageModelBuilder = NativeStatisticalLanguageModel.Builder()
        let customURL = userData.appendingPathComponent("custom_words.tsv")
        var shapeEntries = shape.map(\.entry)
        if FileManager.default.fileExists(atPath: customURL.path) {
            shapeEntries.insert(contentsOf: try Self.readCodedEntries(at: customURL, baseWeight: 3_000_000), at: 0)
        }
        self.shapeEntries = Self.sortedForPrefixSearch(shapeEntries)
        shapeCodesByText = Self.shapeCodesByText(shapeEntries)

        let pinyinRows = allEntries.filter { $0.source == .pinyin }.map(\.entry)
        let essayRows = allEntries.filter { $0.source == .essay }.map(\.entry)
        let characterRows = pinyinRows
        var primaryPinyin = [Character: String]()
        for entry in characterRows where entry.text.count == 1 {
            guard let character = entry.text.first else { continue }
            if primaryPinyin[character] == nil {
                primaryPinyin[character] = entry.code
            }
        }

        var pinyin = characterRows.map {
            NativeDictionaryEntry(text: $0.text, code: Self.normalizedPinyin($0.code), weight: $0.weight, order: $0.order)
        }
        var flypyPhonetic = characterRows.compactMap { entry -> NativeDictionaryEntry? in
            guard let code = Self.flypySyllable(entry.code) else { return nil }
            return NativeDictionaryEntry(
                text: entry.text,
                code: code,
                weight: entry.weight,
                order: entry.order
            )
        }

        var order = pinyin.count
        var simplifiedCharacterCache = [Character: String]()
        func simplifiedText(_ text: String) -> String {
            text.reduce(into: "") { result, character in
                if let cached = simplifiedCharacterCache[character] {
                    result += cached
                    return
                }
                let source = String(character)
                let simplified = source.applyingTransform(
                    StringTransform(rawValue: "Hant-Hans"),
                    reverse: false
                ) ?? source
                simplifiedCharacterCache[character] = simplified
                result += simplified
            }
        }
        for entry in essayRows {
            let simplified = simplifiedText(entry.text)
            if entry.weight >= 500 {
                languageModelBuilder.observe(text: simplified, frequency: entry.weight)
            }
            var code = ""
            var flypyCode = ""
            var complete = true
            for character in simplified {
                guard let syllable = primaryPinyin[character],
                    let encodedSyllable = Self.flypySyllable(syllable)
                else {
                    complete = false
                    break
                }
                code += syllable
                flypyCode += encodedSyllable
            }
            guard complete else { continue }
            pinyin.append(NativeDictionaryEntry(
                text: simplified,
                code: code,
                weight: entry.weight,
                order: order
            ))
            flypyPhonetic.append(NativeDictionaryEntry(
                text: simplified,
                code: flypyCode,
                weight: entry.weight,
                order: order
            ))
            order += 1
        }

        pinyinEntries = Self.sortedForPrefixSearch(pinyin)
        flypyPhoneticEntries = Self.sortedForPrefixSearch(flypyPhonetic)
        languageModel = languageModelBuilder.build()
    }

    private enum ConsolidatedSource {
        case flypy
        case pinyin
        case essay
    }

    private struct ConsolidatedEntry {
        let entry: NativeDictionaryEntry
        let source: ConsolidatedSource
    }

    private static func readConsolidatedEntries(at url: URL) throws -> [ConsolidatedEntry] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var entries = [ConsolidatedEntry]()
        for line in contents.split(whereSeparator: \.isNewline) {
            if line.isEmpty || line.first == "#" || line.first == "-" { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5,
                let weight = Int(fields[2]),
                let order = Int(fields[4])
            else { continue }
            let source: ConsolidatedSource?
            switch fields[3] {
            case "flypy": source = .flypy
            case "pinyin": source = .pinyin
            case "essay": source = .essay
            default: source = nil
            }
            guard let source else { continue }
            let text = String(fields[0])
            let code = String(fields[1]).lowercased()
            guard !text.isEmpty, !code.isEmpty,
                code.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'" ) })
            else { continue }
            entries.append(ConsolidatedEntry(
                entry: NativeDictionaryEntry(text: text, code: code, weight: weight, order: order),
                source: source
            ))
        }
        return entries
    }

    func candidates(for code: String, schema: FengYuSchema, limit: Int = 100) -> [String] {
        let entries: [NativeDictionaryEntry]
        switch schema {
        case .flypy:
            entries = shapeEntries
        case .flypyPhonetic:
            entries = flypyPhoneticEntries
        case .fullPinyin:
            entries = pinyinEntries
        }
        guard !code.isEmpty else { return [] }

        let normalized = schema == .fullPinyin ? Self.normalizedPinyin(code) : code.lowercased()
        let start = Self.lowerBound(in: entries, prefix: normalized)
        var matches = [NativeDictionaryEntry]()
        var index = start
        while index < entries.count, entries[index].code.hasPrefix(normalized) {
            matches.append(entries[index])
            index += 1
            if matches.count >= 20_000 { break }
        }
        matches.sort {
            if schema == .flypy, normalized.count < 4 {
                let lhsSingleCharacter = $0.text.count == 1
                let rhsSingleCharacter = $1.text.count == 1
                if lhsSingleCharacter != rhsSingleCharacter { return lhsSingleCharacter }
            }
            let lhsExact = $0.code == normalized
            let rhsExact = $1.code == normalized
            if lhsExact != rhsExact { return lhsExact }
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.order < $1.order
        }

        let sentenceCandidates: [String]
        switch schema {
        case .flypy:
            sentenceCandidates = []
        case .flypyPhonetic, .fullPinyin:
            sentenceCandidates = Self.sentenceCandidates(
                for: normalized,
                in: entries,
                schema: schema,
                languageModel: languageModel,
                limit: min(limit, 20)
            )
        }

        var seen = Set<String>()
        var result = [String]()
        let rankedMatches: [String]
        if schema == .flypy {
            rankedMatches = matches.map(\.text)
        } else {
            let exactMatches = matches.filter { $0.code == normalized }.map(\.text)
            let prefixMatches = matches.filter { $0.code != normalized }.map(\.text)
            rankedMatches = Self.rankedUniqueTexts(
                exactMatches + sentenceCandidates,
                languageModel: languageModel
            ) + prefixMatches
        }
        for text in rankedMatches where seen.insert(text).inserted {
            result.append(text)
            if result.count == limit { break }
        }
        return result
    }

    func shapeCodeComment(for text: String, matchingPrefix prefix: String) -> String? {
        guard !prefix.isEmpty, let codes = shapeCodesByText[text] else { return nil }
        let matches = codes.filter { $0.hasPrefix(prefix) }
        guard !matches.isEmpty else { return nil }
        let longerMatches = matches.filter { $0.count > prefix.count }
        return (longerMatches.isEmpty ? matches : longerMatches)
            .prefix(3)
            .joined(separator: " / ")
    }

    private static func sentenceCandidates(
        for code: String,
        in entries: [NativeDictionaryEntry],
        schema: FengYuSchema,
        languageModel: NativeStatisticalLanguageModel,
        limit: Int
    ) -> [String] {
        let bytes = Array(code.utf8)
        guard !bytes.isEmpty else { return [] }

        let pathLimit = max(limit, 12)
        let maximumTokenLength = 24
        var paths = Array(repeating: [NativeSentencePath](), count: bytes.count + 1)
        paths[0] = [NativeSentencePath(text: "", unigramScore: 0, segmentCount: 0)]

        for position in bytes.indices where !paths[position].isEmpty {
            let upperBound = min(bytes.count, position + maximumTokenLength)
            guard position < upperBound else { continue }
            for end in (position + 1)...upperBound {
                if schema == .flypyPhonetic, !(end - position).isMultiple(of: 2) {
                    continue
                }
                let token = String(decoding: bytes[position..<end], as: UTF8.self)
                let tokenEntries = exactEntries(for: token, in: entries, limit: 4)
                guard !tokenEntries.isEmpty else { continue }

                for path in paths[position] {
                    for entry in tokenEntries {
                        paths[end].append(NativeSentencePath(
                            text: path.text + entry.text,
                            unigramScore: path.unigramScore + log1p(Double(max(entry.weight, 0))),
                            segmentCount: path.segmentCount + 1
                        ))
                    }
                }
                paths[end] = rankedUniquePaths(
                    paths[end],
                    languageModel: languageModel,
                    limit: pathLimit
                )
            }
        }

        return rankedUniquePaths(
            paths[bytes.count],
            languageModel: languageModel,
            limit: limit
        ).map(\.text)
    }

    private static func exactEntries(
        for code: String,
        in entries: [NativeDictionaryEntry],
        limit: Int
    ) -> [NativeDictionaryEntry] {
        let start = lowerBound(in: entries, prefix: code)
        guard start < entries.count, entries[start].code == code else { return [] }
        var result = [NativeDictionaryEntry]()
        var index = start
        while index < entries.count, entries[index].code == code, result.count < limit {
            result.append(entries[index])
            index += 1
        }
        return result
    }

    private static func rankedUniquePaths(
        _ paths: [NativeSentencePath],
        languageModel: NativeStatisticalLanguageModel,
        limit: Int
    ) -> [NativeSentencePath] {
        var seen = Set<String>()
        return paths.map { path in (path, languageModel.score(path: path)) }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.text < $1.0.text
            }
            .map(\.0)
            .filter { seen.insert($0.text).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func rankedUniqueTexts(
        _ texts: [String],
        languageModel: NativeStatisticalLanguageModel
    ) -> [String] {
        var seen = Set<String>()
        return texts.enumerated()
            .filter { seen.insert($0.element).inserted }
            .map { ($0.offset, $0.element, languageModel.score(text: $0.element)) }
            .sorted {
                if $0.2 != $1.2 { return $0.2 > $1.2 }
                return $0.0 < $1.0
            }
            .map(\.1)
    }

    private static func readCodedEntries(at url: URL, baseWeight: Int) throws -> [NativeDictionaryEntry] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var entries = [NativeDictionaryEntry]()
        for line in contents.split(whereSeparator: \.isNewline) {
            if line.isEmpty || line.first == "#" || line.first == "-" { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let text = String(fields[0])
            let code = String(fields[1]).lowercased()
            guard !text.isEmpty, !code.isEmpty,
                code.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'") })
            else { continue }
            let explicitWeight = fields.count > 2 ? Int(fields[2]) : nil
            entries.append(NativeDictionaryEntry(
                text: text,
                code: code,
                weight: explicitWeight ?? max(0, baseWeight - entries.count),
                order: entries.count
            ))
        }
        return entries
    }

    private static func sortedForPrefixSearch(_ entries: [NativeDictionaryEntry]) -> [NativeDictionaryEntry] {
        entries.sorted {
            if $0.code != $1.code { return $0.code < $1.code }
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.order < $1.order
        }
    }

    private static func shapeCodesByText(
        _ entries: [NativeDictionaryEntry]
    ) -> [String: [String]] {
        var result = [String: [String]]()
        var seen = [String: Set<String>]()
        for entry in entries where entry.code.count <= 4 {
            if seen[entry.text, default: []].insert(entry.code).inserted {
                result[entry.text, default: []].append(entry.code)
            }
        }
        for text in Array(result.keys) {
            result[text]?.sort {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0 < $1
            }
        }
        return result
    }

    private static func lowerBound(in entries: [NativeDictionaryEntry], prefix: String) -> Int {
        var lower = 0
        var upper = entries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if entries[middle].code < prefix {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func normalizedPinyin(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter }
    }

    private static func flypySyllable(_ rawValue: String) -> String? {
        let value = rawValue.lowercased().replacingOccurrences(of: "ü", with: "v")
        let zeroInitial: [String: String] = [
            "a": "aa", "ai": "ai", "an": "an", "ang": "ah", "ao": "ao",
            "e": "ee", "ei": "ei", "en": "en", "eng": "eg", "er": "er",
            "o": "oo", "ou": "ou",
        ]
        if let code = zeroInitial[value] { return code }

        let initial: String
        let final: String
        if value.hasPrefix("zh") || value.hasPrefix("ch") || value.hasPrefix("sh") {
            initial = String(value.prefix(2))
            final = String(value.dropFirst(2))
        } else {
            guard let first = value.first else { return nil }
            initial = String(first)
            final = String(value.dropFirst())
        }
        let initialKey: [String: String] = ["zh": "v", "ch": "i", "sh": "u"]
        let finalKey: [String: String] = [
            "a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v",
            "iu": "q", "ei": "w", "uan": "r", "ue": "t", "ve": "t",
            "un": "y", "uo": "o", "ie": "p", "iong": "s", "ong": "s",
            "ing": "k", "uai": "k", "ai": "d", "en": "f", "eng": "g",
            "iang": "l", "uang": "l", "ang": "h", "ian": "m", "an": "j",
            "ou": "z", "ua": "x", "ia": "x", "iao": "n", "ao": "c",
            "ui": "v", "in": "b",
        ]
        guard let second = finalKey[final] else { return nil }
        return (initialKey[initial] ?? initial) + second
    }
}

struct InputEngineDiagnostics: Equatable, Sendable {
    let activeSessionCount: Int
    let snapshotAllocationCount: Int
    let residentMemoryBytes: UInt64
}

final class InputService: @unchecked Sendable {
    let paths: InputServicePaths
    let version = "native-1.0"
    fileprivate let dictionary: NativeDictionary
    private let lock = NSLock()
    private var activeSessions = 0

    init(paths: InputServicePaths, minLogLevel: Int32 = 2) throws {
        self.paths = paths
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.userData, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let customWords = paths.userData.appendingPathComponent("custom_words.tsv")
        if !fileManager.fileExists(atPath: customWords.path) {
            try "# 词条<Tab>编码<Tab>可选权重\n".write(to: customWords, atomically: true, encoding: .utf8)
        }
        dictionary = try NativeDictionary(sharedData: paths.sharedData, userData: paths.userData)
        _ = minLogLevel
    }

    func makeSession() throws -> InputSession {
        lock.lock()
        activeSessions += 1
        lock.unlock()
        return InputSession(service: self)
    }

    fileprivate func sessionDidClose() {
        lock.lock()
        activeSessions = max(0, activeSessions - 1)
        lock.unlock()
    }

    func diagnostics() -> InputEngineDiagnostics? {
        lock.lock()
        let count = activeSessions
        lock.unlock()
        return InputEngineDiagnostics(
            activeSessionCount: count,
            snapshotAllocationCount: 0,
            residentMemoryBytes: 0
        )
    }
}

final class InputSession: @unchecked Sendable {
    private struct SessionCandidate {
        let text: String
        let comment: String?
    }

    private enum Key {
        static let backspace: Int32 = 0xFF08
        static let tab: Int32 = 0xFF09
        static let `return`: Int32 = 0xFF0D
        static let escape: Int32 = 0xFF1B
        static let left: Int32 = 0xFF51
        static let up: Int32 = 0xFF52
        static let right: Int32 = 0xFF53
        static let down: Int32 = 0xFF54
        static let pageUp: Int32 = 0xFF55
        static let pageDown: Int32 = 0xFF56
        static let shiftLeft: Int32 = 0xFFE1
        static let shiftRight: Int32 = 0xFFE2
    }

    private let service: InputService
    private let lock = NSRecursiveLock()
    private var schema: FengYuSchema = .flypy
    private var buffer = ""
    private var candidates = [SessionCandidate]()
    private var highlightedIndex = 0
    private var pageNumber = 0
    private var reverseLookupMarkerOffset: Int?
    private var pendingCommit: String?
    private var options: [String: Bool] = [
        "ascii_mode": false,
        "full_shape": false,
        "simplification": true,
        "zh_simp": true,
        "zh_trad": false,
        "ascii_punct": false,
    ]
    private var leftShiftPending = false
    private let pageSize = 5

    fileprivate init(service: InputService) {
        self.service = service
    }

    deinit {
        service.sessionDidClose()
    }

    @discardableResult
    func process(keyCode: Int32, modifierMask: Int32 = 0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pendingCommit = nil

        if keyCode == Key.shiftLeft {
            if modifierMask & KeyMapper.ModifierMask.release != 0 {
                defer { leftShiftPending = false }
                guard leftShiftPending else { return false }
                if !buffer.isEmpty {
                    // Shift mode switching commits the literal preedit code;
                    // candidate conversion remains reserved for selection/commit.
                    pendingCommit = buffer
                    clearComposition(keepingCommit: true)
                }
                options["ascii_mode", default: false].toggle()
                return true
            }
            leftShiftPending = true
            return false
        }
        if keyCode == Key.shiftRight { return false }
        if keyCode != Key.shiftLeft { leftShiftPending = false }

        if handleOptionShortcut(keyCode: keyCode, modifierMask: modifierMask) { return true }
        if modifierMask & (KeyMapper.ModifierMask.control | KeyMapper.ModifierMask.option) != 0 {
            return false
        }
        if options["ascii_mode"] == true { return false }

        switch keyCode {
        case Key.backspace:
            if let markerOffset = reverseLookupMarkerOffset, buffer.count == markerOffset {
                reverseLookupMarkerOffset = nil
                updateCandidates()
                return true
            }
            guard !buffer.isEmpty else { return false }
            buffer.removeLast()
            updateCandidates()
            return true
        case Key.escape, Key.tab:
            guard !buffer.isEmpty else { return false }
            clearComposition()
            return true
        case Key.return:
            guard !buffer.isEmpty else { return false }
            pendingCommit = buffer
            clearComposition(keepingCommit: true)
            return true
        case Key.left, Key.up:
            guard !candidates.isEmpty else { return false }
            highlightedIndex = max(0, highlightedIndex - 1)
            pageNumber = highlightedIndex / pageSize
            return true
        case Key.right, Key.down:
            guard !candidates.isEmpty else { return false }
            highlightedIndex = min(candidates.count - 1, highlightedIndex + 1)
            pageNumber = highlightedIndex / pageSize
            return true
        case Key.pageUp:
            return page(up: true)
        case Key.pageDown:
            return page(up: false)
        case 0x20:
            guard !buffer.isEmpty else { return false }
            commitSelectedCandidate()
            return true
        default:
            break
        }

        if keyCode == 0x2D, page(up: true) { return true }
        if keyCode == 0x3D, page(up: false) { return true }

        if keyCode >= 0x31, keyCode <= 0x39, !buffer.isEmpty {
            return selectCandidate(at: Int(keyCode - 0x31))
        }
        if let scalar = UnicodeScalar(UInt32(bitPattern: keyCode)) {
            let character = Character(scalar)
            if character == "~", schema == .flypy {
                guard !buffer.isEmpty, !candidates.isEmpty else { return false }
                if reverseLookupMarkerOffset == nil {
                    reverseLookupMarkerOffset = buffer.count
                } else {
                    reverseLookupMarkerOffset = nil
                }
                updateCandidates()
                return true
            }
            if character.isASCII, character.isLetter {
                guard modifierMask & KeyMapper.ModifierMask.shift == 0 else { return false }
                // A complete Flypy code with ambiguous candidates is committed
                // when the user starts the next syllable, matching the normal
                // continuous-input behavior without requiring Space.
                if schema == .flypy, reverseLookupMarkerOffset == nil,
                    buffer.count >= 4, candidates.count > 1
                {
                    commitSelectedCandidate()
                }
                buffer.append(Character(String(character).lowercased()))
                updateCandidates()
                if schema == .flypy, reverseLookupMarkerOffset == nil,
                    buffer.count >= 4, candidates.count == 1
                {
                    commitSelectedCandidate()
                }
                return true
            }
            if character == "'", schema == .fullPinyin {
                buffer.append(character)
                updateCandidates()
                return true
            }
            if let punctuation = punctuation(for: character) {
                if !buffer.isEmpty { commitSelectedCandidate(suffix: punctuation) }
                else { pendingCommit = punctuation }
                return true
            }
        }
        return false
    }

    @discardableResult
    func simulate(sequence: String) -> Bool {
        var consumed = false
        for scalar in sequence.unicodeScalars {
            consumed = process(keyCode: Int32(bitPattern: scalar.value)) || consumed
        }
        return consumed
    }

    @discardableResult
    func commitComposition() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return false }
        commitSelectedCandidate()
        return true
    }

    func clearComposition() {
        lock.lock()
        clearComposition(keepingCommit: false)
        lock.unlock()
    }

    @discardableResult
    func selectSchema(identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let selected = FengYuSchema(rawValue: identifier) else { return false }
        schema = selected
        clearComposition(keepingCommit: false)
        return true
    }

    @discardableResult
    func setOption(_ name: String, enabled: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard options[name] != nil else { return false }
        options[name] = enabled
        if !buffer.isEmpty, ["simplification", "zh_simp", "zh_trad"].contains(name) {
            updateCandidates()
        }
        return true
    }

    func option(_ name: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return options[name]
    }

    @discardableResult
    func selectCandidate(at index: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let absoluteIndex = pageNumber * pageSize + index
        guard candidates.indices.contains(absoluteIndex) else { return false }
        highlightedIndex = absoluteIndex
        commitSelectedCandidate()
        return true
    }

    func readSnapshot() throws -> InputSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let commit = pendingCommit
        pendingCommit = nil
        let pageStart = pageNumber * pageSize
        let pageEnd = min(pageStart + pageSize, candidates.count)
        let pageCandidates = pageStart < pageEnd ? Array(candidates[pageStart..<pageEnd]) : []
        let compositionText = displayedCompositionText()
        let composition = compositionText.isEmpty ? nil : CompositionSnapshot(
            text: compositionText,
            selectionRange: NSRange(location: compositionText.utf16.count, length: 0),
            cursorPosition: compositionText.utf16.count
        )
        return InputSnapshot(
            commitText: commit,
            composition: composition,
            menu: MenuSnapshot(
                pageSize: pageSize,
                pageNumber: pageNumber,
                isLastPage: pageEnd >= candidates.count,
                highlightedIndex: max(0, highlightedIndex - pageStart),
                candidates: pageCandidates.map {
                    CandidateSnapshot(text: $0.text, comment: $0.comment)
                }
            ),
            status: StatusSnapshot(
                schemaIdentifier: schema.rawValue,
                schemaName: schema.displayName,
                isComposing: !compositionText.isEmpty,
                isASCIIMode: options["ascii_mode"] == true,
                isDisabled: false
            )
        )
    }

    private func updateCandidates() {
        let transform = StringTransform(
            rawValue: options["simplification"] == false ? "Hans-Hant" : "Hant-Hans"
        )
        var seen = Set<String>()
        candidates = service.dictionary.candidates(for: buffer, schema: schema).compactMap { text in
            let converted = text.applyingTransform(transform, reverse: false) ?? text
            guard seen.insert(converted).inserted else { return nil }
            let comment = reverseLookupMarkerOffset == nil ? nil
                : service.dictionary.shapeCodeComment(for: text, matchingPrefix: buffer)
            return SessionCandidate(text: converted, comment: comment)
        }
        highlightedIndex = 0
        pageNumber = 0
    }

    private func commitSelectedCandidate(suffix: String = "") {
        let text = candidates.indices.contains(highlightedIndex)
            ? candidates[highlightedIndex].text
            : buffer
        pendingCommit = text + suffix
        clearComposition(keepingCommit: true)
    }

    private func clearComposition(keepingCommit: Bool) {
        buffer = ""
        candidates = []
        highlightedIndex = 0
        pageNumber = 0
        reverseLookupMarkerOffset = nil
        if !keepingCommit { pendingCommit = nil }
    }

    private func page(up: Bool) -> Bool {
        if up {
            guard pageNumber > 0 else { return false }
            pageNumber -= 1
        } else {
            guard (pageNumber + 1) * pageSize < candidates.count else { return false }
            pageNumber += 1
        }
        highlightedIndex = pageNumber * pageSize
        return true
    }

    private func displayedCompositionText() -> String {
        guard let markerOffset = reverseLookupMarkerOffset else { return buffer }
        let insertionIndex = buffer.index(buffer.startIndex, offsetBy: markerOffset)
        var result = buffer
        result.insert("~", at: insertionIndex)
        return result
    }

    private func handleOptionShortcut(keyCode: Int32, modifierMask: Int32) -> Bool {
        let control = modifierMask & KeyMapper.ModifierMask.control != 0
        let shift = modifierMask & KeyMapper.ModifierMask.shift != 0
        if control, keyCode == 106 {
            options["simplification", default: true].toggle()
            options["zh_simp"] = options["simplification"]
            options["zh_trad"] = !(options["simplification"] ?? true)
            if !buffer.isEmpty { updateCandidates() }
            return true
        }
        if control, keyCode == 46 {
            options["ascii_punct", default: false].toggle()
            return true
        }
        if shift, keyCode == 0x20 {
            options["full_shape", default: false].toggle()
            return true
        }
        return false
    }

    private func punctuation(for character: Character) -> String? {
        let ascii = String(character)
        if options["ascii_punct"] == true { return ascii }
        let mapping: [Character: String] = [
            ",": "，", ".": "。", "/": "、", "?": "？", ";": "；", ":": "：",
            "!": "！", "(": "（", ")": "）", "[": "【", "]": "】",
        ]
        if let mapped = mapping[character] { return mapped }
        if options["full_shape"] == true, let scalar = character.unicodeScalars.first,
            scalar.value >= 0x21, scalar.value <= 0x7E,
            let fullWidth = UnicodeScalar(scalar.value + 0xFEE0)
        {
            return String(fullWidth)
        }
        return nil
    }
}

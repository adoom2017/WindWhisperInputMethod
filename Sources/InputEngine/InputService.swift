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

private final class NativeDictionary: @unchecked Sendable {
    private let shapeEntries: [NativeDictionaryEntry]
    private let pinyinEntries: [NativeDictionaryEntry]
    private let flypyPhoneticEntries: [NativeDictionaryEntry]

    init(sharedData: URL, userData: URL) throws {
        let dictionaryURL = sharedData.appendingPathComponent("fy.dict.yaml")
        guard FileManager.default.fileExists(atPath: dictionaryURL.path) else {
            throw InputEngineError.missingBundledData
        }

        let allEntries = try Self.readConsolidatedEntries(at: dictionaryURL)
        let shape = allEntries.filter { $0.source == .flypy }
        let customURL = userData.appendingPathComponent("custom_words.tsv")
        var shapeEntries = shape.map(\.entry)
        if FileManager.default.fileExists(atPath: customURL.path) {
            shapeEntries.insert(contentsOf: try Self.readCodedEntries(at: customURL, baseWeight: 3_000_000), at: 0)
        }
        self.shapeEntries = Self.sortedForPrefixSearch(shapeEntries)

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
        for entry in essayRows {
            let text = entry.text
            var code = ""
            var flypyCode = ""
            var complete = true
            for character in text {
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
            pinyin.append(NativeDictionaryEntry(text: text, code: code, weight: entry.weight, order: order))
            flypyPhonetic.append(NativeDictionaryEntry(
                text: text,
                code: flypyCode,
                weight: entry.weight,
                order: order
            ))
            order += 1
        }

        pinyinEntries = Self.sortedForPrefixSearch(pinyin)
        flypyPhoneticEntries = Self.sortedForPrefixSearch(flypyPhonetic)
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
        var seen = Set<String>()
        var result = [String]()
        for entry in matches where seen.insert(entry.text).inserted {
            result.append(entry.text)
            if result.count == limit { break }
        }
        return result
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
    private var candidates = [String]()
    private var highlightedIndex = 0
    private var pageNumber = 0
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
                if !buffer.isEmpty { commitSelectedCandidate() }
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
            guard pageNumber > 0 else { return false }
            pageNumber -= 1
            highlightedIndex = pageNumber * pageSize
            return true
        case Key.pageDown:
            guard (pageNumber + 1) * pageSize < candidates.count else { return false }
            pageNumber += 1
            highlightedIndex = pageNumber * pageSize
            return true
        case 0x20:
            guard !buffer.isEmpty else { return false }
            commitSelectedCandidate()
            return true
        default:
            break
        }

        if keyCode >= 0x31, keyCode <= 0x39, !buffer.isEmpty {
            return selectCandidate(at: Int(keyCode - 0x31))
        }
        if let scalar = UnicodeScalar(UInt32(bitPattern: keyCode)) {
            let character = Character(scalar)
            if character.isASCII, character.isLetter {
                guard modifierMask & KeyMapper.ModifierMask.shift == 0 else { return false }
                buffer.append(Character(String(character).lowercased()))
                updateCandidates()
                if schema == .flypy, buffer.count >= 4, candidates.count == 1 {
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
        let composition = buffer.isEmpty ? nil : CompositionSnapshot(
            text: buffer,
            selectionRange: NSRange(location: buffer.utf16.count, length: 0),
            cursorPosition: buffer.utf16.count
        )
        return InputSnapshot(
            commitText: commit,
            composition: composition,
            menu: MenuSnapshot(
                pageSize: pageSize,
                pageNumber: pageNumber,
                isLastPage: pageEnd >= candidates.count,
                highlightedIndex: max(0, highlightedIndex - pageStart),
                candidates: pageCandidates.map { CandidateSnapshot(text: $0, comment: nil) }
            ),
            status: StatusSnapshot(
                schemaIdentifier: schema.rawValue,
                schemaName: schema.displayName,
                isComposing: !buffer.isEmpty,
                isASCIIMode: options["ascii_mode"] == true,
                isDisabled: false
            )
        )
    }

    private func updateCandidates() {
        candidates = service.dictionary.candidates(for: buffer, schema: schema)
        highlightedIndex = 0
        pageNumber = 0
    }

    private func commitSelectedCandidate(suffix: String = "") {
        let text = candidates.indices.contains(highlightedIndex) ? candidates[highlightedIndex] : buffer
        pendingCommit = text + suffix
        clearComposition(keepingCommit: true)
    }

    private func clearComposition(keepingCommit: Bool) {
        buffer = ""
        candidates = []
        highlightedIndex = 0
        pageNumber = 0
        if !keepingCommit { pendingCommit = nil }
    }

    private func handleOptionShortcut(keyCode: Int32, modifierMask: Int32) -> Bool {
        let control = modifierMask & KeyMapper.ModifierMask.control != 0
        let shift = modifierMask & KeyMapper.ModifierMask.shift != 0
        if control, keyCode == 106 {
            options["simplification", default: true].toggle()
            options["zh_simp"] = options["simplification"]
            options["zh_trad"] = !(options["simplification"] ?? true)
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

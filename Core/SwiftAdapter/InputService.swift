import Foundation
#if DEBUG && os(iOS)
import OSLog
private let keyboardPerformanceLogger = Logger(subsystem: "com.shendongchun.inputmethod.windwhisper.ios.keyboard", category: "Performance")
#endif

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

        let identifier = InputEnginePlatform.persistentDataIdentifier
        #if os(macOS)
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        let applicationSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let logsRoot = library.appendingPathComponent("Logs", isDirectory: true)
        #else
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let logsRoot = applicationSupport.appendingPathComponent("Logs", isDirectory: true)
        #endif
        let root = applicationSupport.appendingPathComponent(identifier, isDirectory: true)
        let userData = root.appendingPathComponent("User", isDirectory: true)
        return Self(
            sharedData: sharedData,
            userData: userData,
            logs: logsRoot
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
    // Range maxima let a query split around its next best entry without
    // copying or sorting all entries matching a short prefix.
    final class RankedIndex {
        let entries: [NativeDictionaryEntry]
        private let size: Int
        private var weighted: [Int]
        private var singles: [Int]

        init(_ entries: [NativeDictionaryEntry]) {
            self.entries = entries
            var size = 1
            while size < entries.count { size *= 2 }
            self.size = size
            weighted = Array(repeating: -1, count: size * 2)
            singles = weighted
            for i in entries.indices { weighted[size + i] = i; singles[size + i] = i }
            if size > 1 {
                for i in stride(from: size - 1, through: 1, by: -1) {
                    weighted[i] = better(weighted[i * 2], weighted[i * 2 + 1], singleFirst: false)
                    singles[i] = better(singles[i * 2], singles[i * 2 + 1], singleFirst: true)
                }
            }
        }

        private func better(_ a: Int, _ b: Int, singleFirst: Bool) -> Int {
            if a < 0 { return b }
            if b < 0 { return a }
            let lhs = entries[a], rhs = entries[b]
            if singleFirst, (lhs.text.count == 1) != (rhs.text.count == 1) {
                return lhs.text.count == 1 ? a : b
            }
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight ? a : b }
            if lhs.order != rhs.order { return lhs.order < rhs.order ? a : b }
            return min(a, b)
        }

        func best(in range: Range<Int>, singleFirst: Bool) -> Int? {
            var lower = range.lowerBound + size, upper = range.upperBound + size
            var result = -1
            while lower < upper {
                if lower % 2 == 1 {
                    result = better(result, singleFirst ? singles[lower] : weighted[lower], singleFirst: singleFirst)
                    lower += 1
                }
                if upper % 2 == 1 {
                    upper -= 1
                    result = better(result, singleFirst ? singles[upper] : weighted[upper], singleFirst: singleFirst)
                }
                lower /= 2; upper /= 2
            }
            return result < 0 ? nil : result
        }
    }

    final class CandidateCursor {
        private struct Node {
            let range: Range<Int>
            let winner: Int
        }
        private let index: RankedIndex
        private let singleFirst: Bool
        private let code: String
        private let custom: Set<String>
        private var heap = [Node]()
        private let leading: [String]
        private var leadingOffset = 0
        private var seen = Set<String>()

        init(index: RankedIndex, code: String, singleFirst: Bool, custom: Set<String>, leading: [String], prefixRange: Range<Int>, exactRange: Range<Int>) {
            self.index = index
            self.code = code
            self.singleFirst = singleFirst
            self.custom = custom
            self.leading = leading
            pushRange(prefixRange)
            // Exact entries may have user-defined priority. Their range is
            // small and is inserted separately from the unbounded prefix.
            if custom.isEmpty { pushRange(exactRange) }
            else { for i in exactRange { push(Node(range: i..<(i + 1), winner: i)) } }
        }

        private func precedes(_ a: Node, _ b: Node) -> Bool {
            let lhs = index.entries[a.winner], rhs = index.entries[b.winner]
            let lc = lhs.code == code && custom.contains(lhs.text)
            let rc = rhs.code == code && custom.contains(rhs.text)
            if lc != rc { return lc }
            if singleFirst, (lhs.text.count == 1) != (rhs.text.count == 1) { return lhs.text.count == 1 }
            if (lhs.code == code) != (rhs.code == code) { return lhs.code == code }
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return a.winner < b.winner
        }

        private func pushRange(_ range: Range<Int>) {
            if let winner = index.best(in: range, singleFirst: singleFirst) { push(Node(range: range, winner: winner)) }
        }

        private func push(_ node: Node) {
            heap.append(node)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard precedes(heap[i], heap[parent]) else { break }
                heap.swapAt(i, parent); i = parent
            }
        }

        private func pop() -> Node? {
            guard !heap.isEmpty else { return nil }
            if heap.count == 1 { return heap.removeLast() }
            let result = heap[0]
            heap[0] = heap.removeLast()
            var i = 0
            while i * 2 + 1 < heap.count {
                var child = i * 2 + 1
                if child + 1 < heap.count, precedes(heap[child + 1], heap[child]) { child += 1 }
                guard precedes(heap[child], heap[i]) else { break }
                heap.swapAt(child, i); i = child
            }
            return result
        }

        func next(limit: Int) -> [String] {
            var result = [String]()
            while result.count < limit {
                let text: String
                if leadingOffset < leading.count {
                    text = leading[leadingOffset]; leadingOffset += 1
                } else if let node = pop() {
                    text = index.entries[node.winner].text
                    pushRange(node.range.lowerBound..<node.winner)
                    pushRange((node.winner + 1)..<node.range.upperBound)
                } else { break }
                if seen.insert(text).inserted { result.append(text) }
            }
            return result
        }

        var hasMore: Bool { leadingOffset < leading.count || !heap.isEmpty }
    }
    private struct CandidateCacheKey: Hashable {
        let schemaIdentifier: String
        let code: String
        let limit: Int
    }

#if os(iOS)
    private let baseShapeEntries: [NativeDictionaryEntry]
    private var shapeEntries: [NativeDictionaryEntry]
    private var customShapeTextsByCode: [String: Set<String>]
    private var shapeCodesByText: [String: [String]]
#else
    private let shapeEntries: [NativeDictionaryEntry]
    private let shapeCodesByText: [String: [String]]
#endif
    private let pinyinEntries: [NativeDictionaryEntry]
    private let flypyPhoneticEntries: [NativeDictionaryEntry]
    private var shapeRankedIndex: RankedIndex!
    private var pinyinRankedIndex: RankedIndex!
    private var phoneticRankedIndex: RankedIndex!
    private let buildsRankedIndexes: Bool
    private let languageModel: NativeStatisticalLanguageModel
    private let candidateCacheLock = NSLock()
    private var candidateCache = [CandidateCacheKey: [String]]()
    private var candidateCacheOrder = [CandidateCacheKey]()
    private let candidateCacheCapacity = 128

    init(sharedData: URL, userData: URL, enabledSchemas: Set<FengYuSchema>, buildsRankedIndexes: Bool = false) throws {
        self.buildsRankedIndexes = buildsRankedIndexes
        let dictionaryURL = sharedData.appendingPathComponent("fy.dict.yaml")
        guard FileManager.default.fileExists(atPath: dictionaryURL.path) else {
            throw InputEngineError.missingBundledData
        }

        let needsShape = enabledSchemas.contains(.flypy)
        let needsPinyin = enabledSchemas.contains(.fullPinyin)
        let needsFlypyPhonetic = enabledSchemas.contains(.flypyPhonetic)
        var includedSources = Set<ConsolidatedSource>()
        if needsShape { includedSources.insert(.flypy) }
        if needsPinyin || needsFlypyPhonetic {
            includedSources.formUnion([.pinyin, .essay])
        }

        let allEntries = try Self.readConsolidatedEntries(
            at: dictionaryURL,
            includedSources: includedSources
        )
        let shape = allEntries.filter { $0.source == .flypy }
        var languageModelBuilder = NativeStatisticalLanguageModel.Builder()
        let customURL = userData.appendingPathComponent("custom_words.tsv")
#if os(iOS)
        baseShapeEntries = needsShape ? shape.map(\.entry) : []
        var shapeEntries = baseShapeEntries
        var customEntries = [NativeDictionaryEntry]()
#else
        var shapeEntries = needsShape ? shape.map(\.entry) : []
#endif
        if needsShape, FileManager.default.fileExists(atPath: customURL.path) {
#if os(iOS)
            customEntries = try Self.readCodedEntries(at: customURL, baseWeight: 3_000_000)
            shapeEntries.insert(contentsOf: customEntries, at: 0)
#else
            shapeEntries.insert(contentsOf: try Self.readCodedEntries(at: customURL, baseWeight: 3_000_000), at: 0)
#endif
        }
#if os(iOS)
        customShapeTextsByCode = Dictionary(grouping: customEntries, by: \.code)
            .mapValues { Set($0.map(\.text)) }
#endif
        self.shapeEntries = Self.sortedForPrefixSearch(shapeEntries)
        shapeCodesByText = needsShape ? Self.shapeCodesByText(shapeEntries) : [:]

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

        var pinyin = needsPinyin ? characterRows.map {
            NativeDictionaryEntry(text: $0.text, code: Self.normalizedPinyin($0.code), weight: $0.weight, order: $0.order)
        } : []
        var flypyPhonetic = needsFlypyPhonetic ? characterRows.compactMap { entry -> NativeDictionaryEntry? in
            guard let code = Self.flypySyllable(entry.code) else { return nil }
            return NativeDictionaryEntry(
                text: entry.text,
                code: code,
                weight: entry.weight,
                order: entry.order
            )
        } : []

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
            if needsPinyin {
                pinyin.append(NativeDictionaryEntry(
                    text: simplified,
                    code: code,
                    weight: entry.weight,
                    order: order
                ))
            }
            if needsFlypyPhonetic {
                flypyPhonetic.append(NativeDictionaryEntry(
                    text: simplified,
                    code: flypyCode,
                    weight: entry.weight,
                    order: order
                ))
            }
            order += 1
        }

        pinyinEntries = Self.sortedForPrefixSearch(pinyin)
        flypyPhoneticEntries = Self.sortedForPrefixSearch(flypyPhonetic)
        languageModel = languageModelBuilder.build()
        if buildsRankedIndexes {
            shapeRankedIndex = RankedIndex(self.shapeEntries)
            pinyinRankedIndex = RankedIndex(pinyinEntries)
            phoneticRankedIndex = RankedIndex(flypyPhoneticEntries)
        }
    }

    private enum ConsolidatedSource: Hashable {
        case flypy
        case pinyin
        case essay
    }

    private struct ConsolidatedEntry {
        let entry: NativeDictionaryEntry
        let source: ConsolidatedSource
    }

    private static func readConsolidatedEntries(
        at url: URL,
        includedSources: Set<ConsolidatedSource>
    ) throws -> [ConsolidatedEntry] {
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
            guard let source, includedSources.contains(source) else { continue }
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

#if os(iOS)
    func reloadCustomWords(at url: URL) throws {
        let custom = FileManager.default.fileExists(atPath: url.path)
            ? try Self.readCodedEntries(at: url, baseWeight: 3_000_000) : []
        let entries = Self.sortedForPrefixSearch(custom + baseShapeEntries)
        let codes = Self.shapeCodesByText(entries)
        let customTexts = Dictionary(grouping: custom, by: \.code).mapValues { Set($0.map(\.text)) }
        let rankedIndex = buildsRankedIndexes ? RankedIndex(entries) : nil
        candidateCacheLock.lock()
        defer { candidateCacheLock.unlock() }
        shapeEntries = entries
        shapeRankedIndex = rankedIndex
        shapeCodesByText = codes
        customShapeTextsByCode = customTexts
        candidateCache.removeAll()
        candidateCacheOrder.removeAll()
    }

#endif
    func candidates(for code: String, schema: FengYuSchema, limit: Int = 100) -> [String] {
#if os(iOS)
        candidateCacheLock.lock()
        defer { candidateCacheLock.unlock() }
#endif
        guard !code.isEmpty, limit > 0 else { return [] }
        let normalized = schema == .fullPinyin ? Self.normalizedPinyin(code) : code.lowercased()
        let cacheKey = CandidateCacheKey(
            schemaIdentifier: schema.rawValue,
            code: normalized,
            limit: limit
        )
#if !os(iOS)
        candidateCacheLock.lock()
#endif
        let cached = candidateCache[cacheKey]
#if !os(iOS)
        candidateCacheLock.unlock()
#endif
        if let cached { return cached }

        let entries: [NativeDictionaryEntry]
        switch schema {
        case .flypy:
            entries = shapeEntries
        case .flypyPhonetic:
            entries = flypyPhoneticEntries
        case .fullPinyin:
            entries = pinyinEntries
        }
        let start = Self.lowerBound(in: entries, prefix: normalized)
        var matches = [NativeDictionaryEntry]()
        var index = start
        while index < entries.count, entries[index].code.hasPrefix(normalized) {
            matches.append(entries[index])
            index += 1
            if matches.count >= 20_000 { break }
        }
        matches.sort {
#if os(iOS)
            if schema == .flypy {
                let customTexts = customShapeTextsByCode[normalized] ?? []
                let lhsCustom = $0.code == normalized && customTexts.contains($0.text)
                let rhsCustom = $1.code == normalized && customTexts.contains($1.text)
                if lhsCustom != rhsCustom { return lhsCustom }
            }
#endif
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
#if !os(iOS)
        candidateCacheLock.lock()
#endif
        if candidateCache[cacheKey] == nil {
            if candidateCacheOrder.count >= candidateCacheCapacity {
                let evictedKey = candidateCacheOrder.removeFirst()
                candidateCache.removeValue(forKey: evictedKey)
            }
            candidateCache[cacheKey] = result
            candidateCacheOrder.append(cacheKey)
        }
#if !os(iOS)
        candidateCacheLock.unlock()
#endif
        return result
    }

    func makeCandidateCursor(for code: String, schema: FengYuSchema) -> CandidateCursor {
        candidateCacheLock.lock()
        let index: RankedIndex = schema == .flypy ? shapeRankedIndex
            : schema == .fullPinyin ? pinyinRankedIndex : phoneticRankedIndex
        #if os(iOS)
        let custom = schema == .flypy ? customShapeTextsByCode[code] ?? [] : []
        #else
        let custom = Set<String>()
        #endif
        candidateCacheLock.unlock()
        let normalized = schema == .fullPinyin ? Self.normalizedPinyin(code) : code.lowercased()
        let entries = index.entries
        let start = Self.lowerBound(in: entries, prefix: normalized)
        let exactEnd = Self.lowerBound(in: entries, prefix: normalized + "!")
        let end = Self.lowerBound(in: entries, prefix: normalized + "{")
        let leading = schema == .flypy ? [] : Self.rankedUniqueTexts(
            entries[start..<exactEnd].map(\.text) + Self.sentenceCandidates(
                for: normalized, in: entries, schema: schema, languageModel: languageModel, limit: 20
            ), languageModel: languageModel
        )
        return CandidateCursor(index: index, code: normalized,
            singleFirst: schema == .flypy && normalized.count < 4,
            custom: custom, leading: leading, prefixRange: exactEnd..<end,
            exactRange: schema == .flypy ? start..<exactEnd : start..<start)
    }

    func shapeCodeComment(for text: String, matchingPrefix prefix: String) -> String? {
#if os(iOS)
        candidateCacheLock.lock()
        defer { candidateCacheLock.unlock() }
#endif
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
    fileprivate let candidateLimit: Int?
    private let lock = NSLock()
    private var activeSessions = 0

    init(
        paths: InputServicePaths,
        enabledSchemas: Set<FengYuSchema> = Set(FengYuSchema.allCases),
        candidateLimit: Int? = 100,
        minLogLevel: Int32 = 2
    ) throws {
        self.paths = paths
        self.candidateLimit = candidateLimit.map { max(1, $0) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.userData, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let customWords = paths.userData.appendingPathComponent("custom_words.tsv")
        if !fileManager.fileExists(atPath: customWords.path) {
            try "# 词条<Tab>编码<Tab>可选权重\n".write(to: customWords, atomically: true, encoding: .utf8)
        }
        dictionary = try NativeDictionary(
            sharedData: paths.sharedData,
            userData: paths.userData,
            enabledSchemas: enabledSchemas,
            buildsRankedIndexes: candidateLimit == nil
        )
        _ = minLogLevel
    }

#if os(iOS)
    func reloadCustomWords() throws {
        try dictionary.reloadCustomWords(at: paths.userData.appendingPathComponent("custom_words.tsv"))
    }

#endif
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
    private var candidateCursor: NativeDictionary.CandidateCursor?
    private var convertedCandidateTexts = Set<String>()
    private var hasMoreCandidates = false
    private var queryGeneration: UInt64 = 0
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
    private let candidateBatchSize = 32

    fileprivate init(service: InputService) {
        self.service = service
    }

    deinit {
        service.sessionDidClose()
    }

    @discardableResult
    func process(keyCode: Int32, modifierMask: Int32 = 0) -> Bool {
#if DEBUG && os(iOS)
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            keyboardPerformanceLogger.notice("KeyboardPerf processMs=\((ProcessInfo.processInfo.systemUptime - started) * 1000, privacy: .public)")
        }
#endif
        lock.lock()
        defer { lock.unlock() }
        pendingCommit = nil

        if keyCode == Key.shiftLeft {
            if modifierMask & InputEngineModifierMask.release != 0 {
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
        if modifierMask & (InputEngineModifierMask.control | InputEngineModifierMask.option) != 0 {
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
                guard modifierMask & InputEngineModifierMask.shift == 0 else { return false }
                // A complete Flypy code with ambiguous candidates is committed
                // when the user starts the next syllable, matching the normal
                // continuous-input behavior without requiring Space.
                if schema == .flypy, reverseLookupMarkerOffset == nil,
                    buffer.count >= 4, candidates.count > 1 || hasMoreCandidates
                {
                    commitSelectedCandidate()
                }
                buffer.append(Character(String(character).lowercased()))
                updateCandidates()
                if schema == .flypy, reverseLookupMarkerOffset == nil,
                    buffer.count >= 4, candidates.count == 1, !hasMoreCandidates
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

    func refreshCandidates() {
        lock.lock()
        defer { lock.unlock() }
        updateCandidates()
    }

    @discardableResult
    func loadMoreCandidates(batchSize: Int = 32, generation: UInt64? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard service.candidateLimit == nil,
              generation == nil || generation == queryGeneration else { return false }
        return appendCandidateBatch(limit: max(1, batchSize))
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

    @discardableResult
    func selectCandidate(atAbsoluteIndex index: Int, generation: UInt64? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == nil || generation == queryGeneration,
              candidates.indices.contains(index) else { return false }
        highlightedIndex = index
        commitSelectedCandidate()
        return true
    }

    func readSnapshot() throws -> InputSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let commit = pendingCommit
        pendingCommit = nil
        let pageStart = service.candidateLimit == nil ? 0 : pageNumber * pageSize
        let pageEnd = service.candidateLimit == nil ? candidates.count : min(pageStart + pageSize, candidates.count)
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
                isLastPage: pageEnd >= candidates.count && !hasMoreCandidates,
                highlightedIndex: max(0, highlightedIndex - pageStart),
                candidates: pageCandidates.map {
                    CandidateSnapshot(text: $0.text, comment: $0.comment)
                },
                hasMoreCandidates: hasMoreCandidates,
                queryGeneration: queryGeneration
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
        queryGeneration &+= 1
        candidateCursor = nil
        hasMoreCandidates = false
        candidates.removeAll(keepingCapacity: true)
        convertedCandidateTexts.removeAll(keepingCapacity: true)
        guard !buffer.isEmpty else {
            highlightedIndex = 0
            pageNumber = 0
            return
        }
        if let limit = service.candidateLimit {
            var seen = Set<String>()
            candidates = service.dictionary.candidates(for: buffer, schema: schema, limit: limit).compactMap { text in
                let converted = text.applyingTransform(transform, reverse: false) ?? text
                guard seen.insert(converted).inserted else { return nil }
                return SessionCandidate(text: converted, comment: reverseLookupMarkerOffset == nil ? nil
                    : service.dictionary.shapeCodeComment(for: text, matchingPrefix: buffer))
            }
        } else {
            candidateCursor = service.dictionary.makeCandidateCursor(for: buffer, schema: schema)
            _ = appendCandidateBatch(limit: candidateBatchSize, transform: transform)
        }
        highlightedIndex = 0
        pageNumber = 0
    }

    @discardableResult
    private func appendCandidateBatch(limit: Int, transform suppliedTransform: StringTransform? = nil) -> Bool {
#if DEBUG && os(iOS)
        let started = ProcessInfo.processInfo.systemUptime
        var conversionMs = 0.0
        defer {
            keyboardPerformanceLogger.notice("KeyboardPerf batchMs=\((ProcessInfo.processInfo.systemUptime - started) * 1000, privacy: .public) conversionMs=\(conversionMs, privacy: .public)")
        }
#endif
        guard let candidateCursor, limit > 0 else { return false }
        let transform = suppliedTransform ?? StringTransform(
            rawValue: options["simplification"] == false ? "Hans-Hant" : "Hant-Hans"
        )
        var appended = false
        let targetCount = candidates.count + limit
        while candidates.count < targetCount, candidateCursor.hasMore {
            let needed = targetCount - candidates.count
            let values = candidateCursor.next(limit: needed)
            if values.isEmpty { break }
            for text in values {
#if DEBUG && os(iOS)
                let conversionStarted = ProcessInfo.processInfo.systemUptime
#endif
                let converted = text.applyingTransform(transform, reverse: false) ?? text
#if DEBUG && os(iOS)
                conversionMs += (ProcessInfo.processInfo.systemUptime - conversionStarted) * 1000
#endif
                guard convertedCandidateTexts.insert(converted).inserted else { continue }
                let comment = reverseLookupMarkerOffset == nil ? nil
                    : service.dictionary.shapeCodeComment(for: text, matchingPrefix: buffer)
                candidates.append(SessionCandidate(text: converted, comment: comment))
                appended = true
            }
        }
        hasMoreCandidates = candidateCursor.hasMore
        return appended
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
        convertedCandidateTexts.removeAll(keepingCapacity: true)
        candidateCursor = nil
        hasMoreCandidates = false
        queryGeneration &+= 1
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
        let control = modifierMask & InputEngineModifierMask.control != 0
        let shift = modifierMask & InputEngineModifierMask.shift != 0
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

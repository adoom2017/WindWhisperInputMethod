import CryptoKit
import Foundation

struct Entry {
    let text: String
    let code: String
    let weight: Int
    let source: String
    let order: Int

    struct Key: Hashable {
        let text: String
        let code: String
        let source: String
    }
    var key: Key { Key(text: text, code: code, source: source) }
    var line: String { "\(text)\t\(code)\t\(weight)\t\(source)\t\(order)" }
}

struct GenerationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw GenerationError(message) }
}

func generate(_ input: String, allowed: Set<Character>) throws -> (text: String, counts: [String: Int]) {
    var header = [String]()
    var dataStarted = false
    var entries = [Entry.Key: Entry]()
    let transform = StringTransform(rawValue: "Hant-Hans")
    // Cache whole words so phrase-sensitive conversion is preserved.
    var simplifiedCache = [String: String]()
    for (index, rawLine) in input.components(separatedBy: .newlines).enumerated() {
        if rawLine == "..." { dataStarted = true; header.append(rawLine); continue }
        if !dataStarted { header.append(rawLine); continue }
        if rawLine.isEmpty || rawLine.hasPrefix("#") { continue }
        let fields = rawLine.components(separatedBy: "\t")
        try require(fields.count == 5, "invalid dictionary row at line \(index + 1)")
        let original = fields[0], code = fields[1], source = fields[3]
        try require(!original.isEmpty && ["flypy", "pinyin", "essay"].contains(source),
                    "invalid text/source at line \(index + 1)")
        guard let weight = Int(fields[2]), let order = Int(fields[4]) else {
            throw GenerationError("invalid weight/order at line \(index + 1)")
        }
        try require(!code.isEmpty && code.utf8.allSatisfy { (97...122).contains($0) || $0 == 39 },
                    "invalid code at line \(index + 1)")
        let text: String
        if original.allSatisfy({ allowed.contains($0) }) {
            // Already-standard words need no conversion. ICU Hant-Hans can
            // otherwise swap valid forms such as 苎/苧 on repeated runs.
            text = original
        } else if let cached = simplifiedCache[original] {
            text = cached
        } else {
            guard let converted = original.applyingTransform(transform, reverse: false) else {
                throw GenerationError("cannot simplify text at line \(index + 1)")
            }
            text = converted
            simplifiedCache[original] = text
        }
        // Simplify BEFORE filtering: 電腦 must survive as 电脑.
        guard !text.isEmpty, text.allSatisfy({ allowed.contains($0) }) else { continue }
        let entry = Entry(text: text, code: code, weight: weight, source: source, order: order)
        // Preserve alternate readings, codes, and sources. Within one key,
        // retain the highest weight, then the earliest original order.
        if let previous = entries[entry.key],
           previous.weight > weight || (previous.weight == weight && previous.order <= order) {
            continue
        }
        entries[entry.key] = entry
    }
    try require(dataStarted, "dictionary header terminator is missing")
    let sourceOrder = ["flypy": 0, "pinyin": 1, "essay": 2]
    let retained = entries.values.filter {
        ($0.source == "flypy" && $0.code.count <= 4) || $0.source == "pinyin"
            || ($0.source == "essay" && $0.weight >= 1_000)
    }.sorted {
        if $0.source != $1.source { return sourceOrder[$0.source]! < sourceOrder[$1.source]! }
        if $0.order != $1.order { return $0.order < $1.order }
        if $0.code != $1.code { return $0.code < $1.code }
        return $0.text < $1.text
    }
    let counts = Dictionary(grouping: retained, by: \.source).mapValues(\.count)
    return ((header + retained.map(\.line)).joined(separator: "\n") + "\n", counts)
}

func verifyNormalization() throws {
    let rows = [
        "電腦\tdiannao\t500\tessay\t0",
        "电脑\tdiannao\t2000\tessay\t2",
        "電腦\tdiannao\t2000\tessay\t1",
        "電腦\tdmnc\t100\tflypy\t3",
        "電腦\tdn\t90\tflypy\t4",
        "電腦\tdmnccc\t100\tflypy\t5",
        "腦\tnao\t100\tpinyin\t6",
        "重\tzhong\t100\tpinyin\t7",
        "重\tchong\t90\tpinyin\t8",
        "電腦\tdiannao\t2000\tpinyin\t9",
        "腦\tnao\t999\tessay\t10",
        "龘\tda\t2000\tessay\t11",
    ]
    let generated = try generate("---\n...\n" + rows.joined(separator: "\n"), allowed: Set("电脑重"))
    let expected = "---\n...\n" + [
        "电脑\tdmnc\t100\tflypy\t3", "电脑\tdn\t90\tflypy\t4",
        "脑\tnao\t100\tpinyin\t6", "重\tzhong\t100\tpinyin\t7",
        "重\tchong\t90\tpinyin\t8", "电脑\tdiannao\t2000\tpinyin\t9",
        "电脑\tdiannao\t2000\tessay\t1",
    ].joined(separator: "\n") + "\n"
    try require(generated.text == expected, "normalization/deduplication regression")
    let repeated = try generate(generated.text, allowed: Set("电脑重"))
    try require(repeated.text == expected, "generation is not idempotent")
    print("PASS normalization: traditional words, weight/order deduplication, alternate codes/readings/sources, filtering, trimming, idempotence")
}

do {
    try verifyNormalization()
    try require(CommandLine.arguments.count == 4, "usage: generate-ios-dictionary.swift <allowed> <source> <output>")
    let allowedData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let checksum = SHA256.hash(data: allowedData).map { String(format: "%02x", $0) }.joined()
    try require(checksum == "9da0c863a53b9d5330b3740d2593ef66be8e15ab8933c2be88222a7d5e1d455f", "allowed character list checksum changed")
    let characters = String(decoding: allowedData, as: UTF8.self).components(separatedBy: .newlines)
        .filter { !$0.hasPrefix("#") }.joined()
    try require(characters.count == 8_105 && Set(characters).count == 8_105, "invalid allowed character list")
    let input = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
    let result = try generate(input, allowed: Set(characters))
    try require(result.text.utf8.count <= 3_500_000, "iOS dictionary exceeds 3.5 MB")
    try result.text.write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
    print("Entries: \(result.counts.sorted { $0.key < $1.key }); bytes: \(result.text.utf8.count)")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

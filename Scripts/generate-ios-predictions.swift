import Foundation

// Builds iOS/Resources/predict.txt from the librime-predict data release:
// one line per committed text, `head<TAB>next<TAB>next...`, best first,
// sorted by UTF-8 bytes so the keyboard can binary-search a mapped file.
// Heads and continuations are limited to words of the iOS dictionary: the
// keyboard commits nothing else as one unit.

struct GenerationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let maximumLength = 4
let maximumContinuations = 10

func generate(_ input: String, words: Set<String>, header: [String]) throws -> (text: String, heads: Int, entries: Int) {
    let transform = StringTransform(rawValue: "Hant-Hans")
    var simplifiedCache = [String: String]()
    func simplified(_ text: String) -> String? {
        // Dictionary words need no conversion (ICU can swap valid forms).
        if words.contains(text) { return text }
        if let cached = simplifiedCache[text] { return cached }
        let converted = text.applyingTransform(transform, reverse: false)
        simplifiedCache[text] = converted
        return converted
    }

    var weights = [String: [String: Int]]()
    for (index, line) in input.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 3, let weight = Int(fields[2]) else {
            throw GenerationError("invalid prediction row at line \(index + 1)")
        }
        // `$` predicts the start of a sentence; the keyboard predicts after commits only.
        guard fields[0] != "$" else { continue }
        guard let head = simplified(String(fields[0])), let next = simplified(String(fields[1])),
              (1...maximumLength).contains(head.count), (1...maximumLength).contains(next.count),
              words.contains(head), words.contains(next)
        else { continue }
        // Traditional and simplified rows can merge; keep the stronger weight.
        weights[head, default: [:]][next] = max(weights[head]?[next] ?? 0, weight)
    }

    var lines = [(key: [UInt8], line: String)]()
    var entries = 0
    for (head, continuations) in weights {
        let best = continuations.sorted {
            $0.value != $1.value ? $0.value > $1.value : Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8))
        }.prefix(maximumContinuations).map(\.key)
        entries += best.count
        lines.append((Array(head.utf8), ([head] + best).joined(separator: "\t")))
    }
    lines.sort { $0.key.lexicographicallyPrecedes($1.key) }
    return ((header + lines.map(\.line)).joined(separator: "\n") + "\n", lines.count, entries)
}

func verify() throws {
    let words: Set<String> = ["我们", "的", "都", "可以", "电脑", "问", "题"]
    let input = "$\t我\t9\n我們\t的\t5\n我们\t都\t7\n我們\t都\t3\n我們\t電腦\t4\n問\t題\t2\n我們\t龘\t9\n我们\t都是\t9\n"
    let result = try generate(input, words: words, header: ["# test"])
    let expected = "# test\n我们\t都\t的\t电脑\n问\t题\n"
    guard result.text == expected else { throw GenerationError("unexpected output:\n\(result.text)") }
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: generate-ios-predictions.swift <iOS fy.dict.yaml> <predict.txt> <output>")
    exit(64)
}
do {
    try verify()
    // Dictionary rows follow the `...` header terminator; the text is the first column.
    let dictionary = try String(contentsOfFile: arguments[1], encoding: .utf8)
    guard let body = dictionary.range(of: "\n...\n") else { throw GenerationError("dictionary header terminator is missing") }
    let words = Set(dictionary[body.upperBound...].split(separator: "\n").compactMap { line in
        line.split(separator: "\t", maxSplits: 1).first.map(String.init)
    })
    let input = try String(contentsOfFile: arguments[2], encoding: .utf8)
    let header = [
        "# WindWhisper input predictions: committed text, then likely next words.",
        "# Source: rime/librime-predict release data-1.0, predict.txt (made from rime essay + octagram)",
        "# License: LGPL-3.0 (rime-essay, rime-octagram-data); converted to Simplified, limited to",
        "# words of iOS/Resources/fy.dict.yaml, at most \(maximumContinuations) continuations per head.",
    ]
    let result = try generate(input, words: words, header: header)
    try result.text.write(toFile: arguments[3], atomically: true, encoding: .utf8)
    print("PASS normalization; \(result.heads) heads, \(result.entries) continuations")
} catch {
    print("FAIL: \(error)")
    exit(1)
}

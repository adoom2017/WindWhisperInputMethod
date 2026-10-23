import Foundation

/// Next-word predictions shown after a commit. The data file
/// (iOS/Resources/predict.txt, see Scripts/generate-ios-predictions.sh) holds
/// one `head<TAB>next<TAB>…` line per head, best first, sorted by UTF-8 bytes.
/// It stays memory-mapped and is binary-searched, so only the line offsets
/// live in the keyboard's limited memory.
final class InputPredictions: @unchecked Sendable {
    /// Longest committed tail looked up, matching the generator's head limit.
    private static let maximumHeadLength = 4

    private let data: Data
    private let lineStarts: [Int32]

    init(contentsOf url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        var starts = [Int32]()
        starts.reserveCapacity(170_000)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var start = 0
            for index in bytes.indices where bytes[index] == 0x0A {
                // Skip empty lines and `#` comments.
                if start < index, bytes[start] != 0x23 { starts.append(Int32(start)) }
                start = index + 1
            }
        }
        lineStarts = starts
    }

    /// Continuations for the end of `text`: those of its longest tail that has
    /// any, so "今天天气很好" falls back to "很好".
    func predictions(after text: String) -> [String] {
        let tail = Array(text.suffix(Self.maximumHeadLength))
        for length in stride(from: tail.count, through: 1, by: -1) {
            let found = lookup(String(tail.suffix(length)))
            if !found.isEmpty { return found }
        }
        return []
    }

    private func lookup(_ head: String) -> [String] {
        let key = Array(head.utf8)
        return data.withUnsafeBytes { raw -> [String] in
            let bytes = raw.bindMemory(to: UInt8.self)
            var low = 0
            var high = lineStarts.count
            while low < high {
                let middle = (low + high) / 2
                let start = Int(lineStarts[middle])
                switch Self.compareHead(in: bytes, at: start, with: key) {
                case ..<0: low = middle + 1
                case 1...: high = middle
                default:
                    var end = start
                    while end < bytes.count, bytes[end] != 0x0A { end += 1 }
                    let line = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
                    return line.split(separator: "\t").dropFirst().map(String.init)
                }
            }
            return []
        }
    }

    /// Compares the head field of the line at `start` with `key`, bytewise.
    private static func compareHead(in bytes: UnsafeBufferPointer<UInt8>, at start: Int, with key: [UInt8]) -> Int {
        var index = start
        for byte in key {
            guard index < bytes.count, bytes[index] != 0x09, bytes[index] != 0x0A else { return -1 }
            if bytes[index] != byte { return bytes[index] < byte ? -1 : 1 }
            index += 1
        }
        guard index < bytes.count, bytes[index] != 0x09, bytes[index] != 0x0A else { return 0 }
        return 1
    }
}

/// Word pairs the user commits in a row (`我们` then `可以`), so their own
/// combinations rise in, or join, the predictions. Kept in the keyboard's
/// private storage as `head<TAB>next<TAB>count<TAB>day`; past `capacity`
/// pairs the weakest are dropped, scoring use count with a 30-day half-life.
@MainActor
final class LearnedPredictions {
    struct Entry: Equatable {
        var count: Int
        /// Days since 1970 of the last use.
        var lastUsed: Int
    }

    static let capacity = 5_000
    /// Pruning goes below capacity so a full store is not rewritten per commit.
    static let retainedAfterPruning = 4_000
    private static let maximumHeadLength = 4
    private static let maximumWordLength = 8
    private static let halfLifeDays = 30.0

    private let url: URL
    private let today: () -> Int
    private(set) var entries = [String: [String: Entry]]()
    private(set) var pairCount = 0
    private var saveTimer: Timer?

    init(url: URL, today: @escaping () -> Int = { Int(Date().timeIntervalSince1970 / 86_400) }) {
        self.url = url
        self.today = today
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in contents.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 4, let count = Int(fields[2]), let day = Int(fields[3]), count > 0,
                  Self.isLearnable(String(fields[0])), Self.isLearnable(String(fields[1]))
            else { continue }
            entries[String(fields[0]), default: [:]][String(fields[1])] = Entry(count: count, lastUsed: day)
            pairCount += 1
        }
        if pairCount > Self.capacity { prune() }
    }

    /// Only Chinese words are learned: raw codes, English and punctuation
    /// commits are not predictions.
    static func isLearnable(_ text: String) -> Bool {
        (1...maximumWordLength).contains(text.count)
            && text.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }

    func record(after previous: String, next: String) {
        guard Self.isLearnable(previous), Self.isLearnable(next) else { return }
        let head = String(previous.suffix(Self.maximumHeadLength))
        if var entry = entries[head]?[next] {
            entry.count = min(entry.count + 1, 1_000_000)
            entry.lastUsed = today()
            entries[head]![next] = entry
        } else {
            entries[head, default: [:]][next] = Entry(count: 1, lastUsed: today())
            pairCount += 1
            if pairCount > Self.capacity { prune() }
        }
        scheduleSave()
    }

    /// Learned words for the longest tail of `text` that has any, best first.
    func predictions(after text: String) -> [(text: String, count: Int)] {
        let tail = Array(text.suffix(Self.maximumHeadLength))
        for length in stride(from: tail.count, through: 1, by: -1) {
            guard let found = entries[String(tail.suffix(length))], !found.isEmpty else { continue }
            return found.sorted {
                let (first, second) = (score($0.value), score($1.value))
                return first != second ? first > second : $0.key < $1.key
            }.map { ($0.key, $0.value.count) }
        }
        return []
    }

    func flush() {
        guard saveTimer != nil else { return }
        saveTimer?.invalidate()
        saveTimer = nil
        let lines = entries.flatMap { head, nexts in
            nexts.map { "\(head)\t\($0.key)\t\($0.value.count)\t\($0.value.lastUsed)\n" }
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try lines.sorted().joined().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("WindWhisper: could not save learned predictions")
        }
    }

    private func score(_ entry: Entry) -> Double {
        Double(entry.count) * pow(0.5, Double(max(0, today() - entry.lastUsed)) / Self.halfLifeDays)
    }

    private func prune() {
        let ranked = entries.flatMap { head, nexts in nexts.map { (head, $0.key, $0.value) } }
            .sorted { score($0.2) > score($1.2) }
        entries = [:]
        for (head, next, entry) in ranked.prefix(Self.retainedAfterPruning) {
            entries[head, default: [:]][next] = entry
        }
        pairCount = min(ranked.count, Self.retainedAfterPruning)
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }
}

import Foundation

@main
struct CandidateSmoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
        let paths = InputServicePaths.temporary(root: root, sharedData: shared)
        let service = try InputService(paths: paths, candidateLimit: nil)
        let bounded = try InputService(paths: paths, candidateLimit: 100_000)
        var firstTimes = [Double](), batchTimes = [Double]()
        for schema in FengYuSchema.allCases {
            for code in ["a", "s", "z", "ni", "ui", "zhong", "nihao", "nihc", "woaini"] {
                let session = try service.makeSession()
                session.selectSchema(identifier: schema.rawValue)
                let reference = try bounded.makeSession()
                reference.selectSchema(identifier: schema.rawValue)
                // Keep complete shape codes visible for ranking comparison.
                if schema == .flypy && code.count >= 4 { continue }
                let start = ProcessInfo.processInfo.systemUptime
                session.simulate(sequence: code)
                var snapshot = try session.readSnapshot()
                firstTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                precondition(snapshot.menu.candidates.count <= 32)
                let generation = snapshot.menu.queryGeneration
                while snapshot.menu.hasMoreCandidates {
                    let start = ProcessInfo.processInfo.systemUptime
                    session.loadMoreCandidates(generation: generation)
                    batchTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    snapshot = try session.readSnapshot()
                }
                reference.simulate(sequence: code)
                var expected = [String]()
                while true {
                    let page = try reference.readSnapshot()
                    expected += page.menu.candidates.map(\.text)
                    if page.menu.isLastPage { break }
                    precondition(reference.process(keyCode: 0xFF56))
                }
                precondition(snapshot.menu.candidates.map(\.text) == expected, "ranking mismatch: \(schema) \(code)")
                if code == "s", schema == .flypy { precondition(expected.count > 100) }
                for selected in [5, 32, expected.count - 1] where expected.indices.contains(selected) {
                    let pick = try service.makeSession()
                    pick.selectSchema(identifier: schema.rawValue)
                    pick.simulate(sequence: code)
                    while try pick.readSnapshot().menu.candidates.count <= selected {
                        precondition(pick.loadMoreCandidates())
                    }
                    precondition(pick.selectCandidate(atAbsoluteIndex: selected))
                    let committed = try pick.readSnapshot().commitText
                    precondition(committed == expected[selected])
                }
                session.process(keyCode: 0xFF08)
                precondition(!session.loadMoreCandidates(generation: generation))
                precondition(!session.selectCandidate(atAbsoluteIndex: 0, generation: generation))
                print("PASS \(schema.rawValue) \(code): \(expected.count) candidates")
            }
        }
        // Each session creates a fresh cursor; unlimited queries do not use
        // the bounded-result cache. Collect enough samples for a useful P95.
        for _ in 0..<20 {
            for schema in FengYuSchema.allCases {
                for code in ["a", "s", "z"] {
                    let session = try service.makeSession()
                    session.selectSchema(identifier: schema.rawValue)
                    let start = ProcessInfo.processInfo.systemUptime
                    session.simulate(sequence: code)
                    firstTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    let next = ProcessInfo.processInfo.systemUptime
                    session.loadMoreCandidates()
                    batchTimes.append((ProcessInfo.processInfo.systemUptime - next) * 1000)
                }
            }
        }
        func p95(_ values: [Double]) -> Double { values.sorted()[min(values.count - 1, Int(Double(values.count) * 0.95))] }
        print("First sequence P95: \(p95(firstTimes)) ms (\(firstTimes.count) samples); batch P95: \(p95(batchTimes)) ms (\(batchTimes.count) samples)")
        precondition(p95(firstTimes) < 16 && p95(batchTimes) < 8)
        for (schema, code, expected) in [
            (FengYuSchema.fullPinyin, "womenkeyiyiqi", "我们可以一起"),
            (.flypyPhonetic, "womfkeyiyiqi", "我们可以一起"),
            (.fullPinyin, "woxiangyaozhege", "我想要这个"),
            (.flypyPhonetic, "woxlycvege", "我想要这个")
        ] {
            let session = try service.makeSession()
            session.selectSchema(identifier: schema.rawValue)
            session.simulate(sequence: code)
            let snapshot = try session.readSnapshot()
            precondition(snapshot.menu.candidates.contains { $0.text == expected }, "missing sentence: \(expected)")
        }
        print("PASS: long sentences in full pinyin and double pinyin")
        try verifyFixtures(root: root.appendingPathComponent("fixtures"))
    }

    static func verifyFixtures(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var rows = (0..<21_050).map { "词\($0)\tab\t\(30_000 - $0)\tflypy\t\($0)" }
        rows += ["独\twxyz\t100\tflypy\t22000", "甲\tzzyy\t100\tflypy\t22001",
                 "乙\tzzyy\t90\tflypy\t22002", "發\tqqqq\t100\tflypy\t22003",
                 "发\tqqqq\t90\tflypy\t22004"]
        try rows.joined(separator: "\n").write(to: root.appendingPathComponent("fy.dict.yaml"), atomically: true, encoding: .utf8)
        let service = try InputService(paths: .temporary(root: root, sharedData: root), candidateLimit: nil)
        for schema in FengYuSchema.allCases {
            let literalSession = try service.makeSession()
            literalSession.selectSchema(identifier: schema.rawValue)
            literalSession.simulate(sequence: "vvvvvv")
            let composing = try literalSession.readSnapshot()
            precondition(composing.composition?.text == "vvvvvv" && composing.menu.candidates.isEmpty)
            precondition(literalSession.process(keyCode: 0xFF0D))
            let committed = try literalSession.readSnapshot()
            precondition(committed.commitText == "vvvvvv" && committed.composition == nil)
            precondition(committed.menu.candidates.isEmpty && !committed.menu.hasMoreCandidates)
            let afterCommit = try literalSession.readSnapshot()
            precondition(afterCommit.commitText == nil)
            precondition(!literalSession.process(keyCode: 0xFF0D))
            literalSession.setOption("ascii_mode", enabled: true)
            precondition(!literalSession.process(keyCode: 0xFF0D))
        }
        print("PASS: Return commits unmatched code once; idle and ASCII Return pass through")
        let session = try service.makeSession()
        session.simulate(sequence: "a")
        var snapshot = try session.readSnapshot()
        while snapshot.menu.hasMoreCandidates {
            session.loadMoreCandidates()
            snapshot = try session.readSnapshot()
        }
        precondition(snapshot.menu.candidates.count == 21_050)
        precondition(snapshot.menu.candidates.last?.text == "词21049")
        let defaultSession = try InputService(paths: .temporary(root: root, sharedData: root)).makeSession()
        defaultSession.simulate(sequence: "a")
        var defaultCount = 0
        while true {
            let page = try defaultSession.readSnapshot()
            precondition(page.menu.candidates.count == 5 && !page.menu.hasMoreCandidates)
            defaultCount += page.menu.candidates.count
            if page.menu.isLastPage { break }
            precondition(defaultSession.process(keyCode: 0xFF56))
        }
        precondition(defaultCount == 100 && !defaultSession.loadMoreCandidates())
        session.clearComposition()
        session.simulate(sequence: "wxyz")
        snapshot = try session.readSnapshot()
        precondition(snapshot.commitText == "独" && snapshot.composition == nil)
        session.simulate(sequence: "zzyy")
        snapshot = try session.readSnapshot()
        precondition(snapshot.commitText == nil && snapshot.menu.candidates.map(\.text) == ["甲", "乙"])
        session.process(keyCode: 97)
        snapshot = try session.readSnapshot()
        precondition(snapshot.commitText == "甲" && snapshot.composition?.text == "a")
        session.clearComposition()
        session.simulate(sequence: "qqqq")
        snapshot = try session.readSnapshot()
        precondition(snapshot.commitText == "发")
        session.setOption("simplification", enabled: false)
        session.simulate(sequence: "qqqq")
        snapshot = try session.readSnapshot()
        precondition(snapshot.commitText == "發")
        session.clearComposition()
        session.simulate(sequence: "wx~")
        snapshot = try session.readSnapshot()
        precondition(snapshot.menu.candidates.first?.comment == "wxyz")
        print("PASS: 21,050 candidates, four-code unique/ambiguous/continuation, conversion deduplication, reverse lookup")
    }
}

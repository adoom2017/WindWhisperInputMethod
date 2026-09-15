import Foundation

@main
struct UserFrequencySmoke {
    static func check(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        precondition(condition, message, file: file, line: line)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let words = ["的", "地", "得", "等", "大", "到", "道", "电", "点", "东", "动", "定"]
        var rows = [String]()
        for (i, word) in words.enumerated() {
            rows += ["\(word)\tde\t\(1000 - i)\tpinyin\t\(i)",
                     "\(word)\tda\t\(1000 - i)\tflypy\t\(i)"]
        }
        rows.append("的\td\t2000\tflypy\t20")
        try rows.joined(separator: "\n").write(to: root.appendingPathComponent("fy.dict.yaml"), atomically: true, encoding: .utf8)
        for limit in [Optional(100), nil] {
            let paths = InputServicePaths.temporary(root: root.appendingPathComponent(limit == nil ? "cursor" : "bounded"), sharedData: root)
            let service = try InputService(paths: paths, candidateLimit: limit)
            // Construct the second service before any selection, as separate IME hosts do.
            let other = try InputService(paths: paths, candidateLimit: limit)
            for schema in FengYuSchema.allCases {
                func query(_ owner: InputService = service, code: String = "d", traditional: Bool = false) throws -> InputSession {
                    let session = try owner.makeSession()
                    session.selectSchema(identifier: schema.rawValue)
                    session.setOption("simplification", enabled: !traditional)
                    session.simulate(sequence: code)
                    return session
                }
                func first(_ owner: InputService = service, code: String = "d", traditional: Bool = false) throws -> String? {
                    try query(owner, code: code, traditional: traditional).readSnapshot().menu.candidates.first?.text
                }
                func choose(_ text: String, owner: InputService = service, traditional: Bool = false) throws {
                    let session = try query(owner, traditional: traditional)
                    while true {
                        let snapshot = try session.readSnapshot()
                        if let index = snapshot.menu.candidates.firstIndex(where: { $0.text == text }) {
                            precondition(limit == nil ? session.selectCandidate(atAbsoluteIndex: index, generation: snapshot.menu.queryGeneration) : session.selectCandidate(at: index))
                            let result = try session.readSnapshot()
                            precondition(result.commitText == text)
                            return
                        }
                        if limit == nil { precondition(session.loadMoreCandidates()) }
                        else { precondition(session.process(keyCode: 0xFF56)) }
                    }
                }
                check(try first() == "的", "schemas must learn independently")
                try choose("电") // Originally on the second page.
                check(try first() == "电")
                check(try first(other) == "电", "other services must observe saved selections")
                check(try first(code: "de") == (schema == .flypy ? nil : "的"), "codes must learn independently")
                try choose("地", owner: other)
                check(try first() == "地", "ties must preserve dictionary order")
                try choose("電", traditional: true)
                check(try first() == "电", "simplified/traditional must share source identity")
                check(try first(traditional: true) == "電")
                let restored = try InputService(paths: paths, candidateLimit: limit)
                check(try first(restored) == "电", "must survive engine restart")
                let history = paths.userData.appendingPathComponent("user_frequency.tsv")
                let before = try Data(contentsOf: history)
                let cancelled = try query()
                precondition(!cancelled.selectCandidate(atAbsoluteIndex: 9999))
                precondition(cancelled.process(keyCode: 0xFF1B))
                let literal = try query(code: "vvvvvv")
                precondition(literal.process(keyCode: 0xFF0D))
                check(try Data(contentsOf: history) == before, "cancelled/invalid/literal commits must not learn")
                print("PASS learning \(schema.rawValue), \(limit == nil ? "cursor" : "bounded")")
            }
        }
        // A learned candidate beyond the initial cursor batch and the bounded
        // search's historical 20,000-row scan limit must still reach the front.
        let deep = root.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let large = (0..<21_050).map { "词\($0)\tab\t\(30_000 - $0)\tflypy\t\($0)" }
        try large.joined(separator: "\n").write(to: deep.appendingPathComponent("fy.dict.yaml"), atomically: true, encoding: .utf8)
        let paths = InputServicePaths.temporary(root: deep, sharedData: deep)
        let service = try InputService(paths: paths, candidateLimit: nil)
        let session = try service.makeSession()
        session.simulate(sequence: "a")
        while try session.readSnapshot().menu.hasMoreCandidates { session.loadMoreCandidates() }
        precondition(session.selectCandidate(atAbsoluteIndex: 21_049))
        for limit in [Optional(100), nil] {
            let next = try InputService(paths: paths, candidateLimit: limit).makeSession()
            next.simulate(sequence: "a")
            check(try next.readSnapshot().menu.candidates.first?.text == "词21049")
        }
        print("PASS learning beyond cursor batches and bounded scan limit")
    }
}

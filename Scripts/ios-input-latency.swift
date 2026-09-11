import Foundation

@main
struct InputLatencyProbe {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
        let schema = FengYuSchema(rawValue: CommandLine.arguments[2])!
        let started = ProcessInfo.processInfo.systemUptime
        let service = try InputService(paths: .temporary(root: root, sharedData: shared), candidateLimit: nil)
        print("startupMs=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
        let session = try service.makeSession()
        session.selectSchema(identifier: schema.rawValue)
        for round in 1...3 {
            session.clearComposition()
            for key in "nihao".utf8 {
                let started = ProcessInfo.processInfo.systemUptime
                _ = session.process(keyCode: Int32(key))
                let snapshot = try session.readSnapshot()
                print("round=\(round) key=\(key) candidates=\(snapshot.menu.candidates.count) elapsedMs=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
            }
        }
    }
}

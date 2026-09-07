import Foundation

@main
struct IOSCustomPhrasesSmoke {
    static func check(_ condition: @autoclosure () throws -> Bool) throws {
        let result = try condition()
        precondition(result)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if let dictionary = CommandLine.arguments.dropFirst().first {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: dictionary), to: root.appendingPathComponent("fy.dict.yaml")
            )
        } else {
            try "字\tzz\t1\tflypy\t0\n字\tzi\t1\tpinyin\t1\n".write(
                to: root.appendingPathComponent("fy.dict.yaml"), atomically: true, encoding: .utf8
            )
        }
        let paths = InputServicePaths.temporary(root: root, sharedData: root)
        let store = CustomWordsStore(fileURL: paths.userData.appendingPathComponent("custom_words.tsv"))
        var document = try store.save(CustomWordsDocument(comments: [], entries: [
            CustomWordEntry(text: "测试专属词组", code: " ZZ ")
        ]))
        precondition(document.entries[0].code == "zz")
        try check(store.load().entries[0].text == "测试专属词组")

        func candidates(_ schema: FengYuSchema, code: String = "zz") throws -> [String] {
            let service = try InputService(paths: paths, enabledSchemas: [schema], candidateLimit: 5)
            let session = try service.makeSession()
            session.selectSchema(identifier: schema.rawValue)
            session.simulate(sequence: code)
            let snapshot = try session.readSnapshot()
            return snapshot.menu.candidates.map(\.text) + [snapshot.commitText].compactMap { $0 }
        }
        try check(candidates(.flypy).contains("测试专属词组"))
        try check(!candidates(.flypyPhonetic).contains("测试专属词组"))
        try check(!candidates(.fullPinyin).contains("测试专属词组"))
        var duplicate = document
        duplicate.entries.append(CustomWordEntry(text: "测试专属词组", code: "zz"))
        do {
            try store.save(duplicate)
            fatalError("Duplicate should be rejected")
        } catch CustomWordsStoreError.duplicateEntry { }
        document.entries[0].text = "修改后的专属词组"
        try store.save(document)
        let edited = try candidates(.flypy)
        precondition(edited.contains("修改后的专属词组") && !edited.contains("测试专属词组"))
        // Keep both the service and composition alive while the file changes.
        let liveService = try InputService(paths: paths, enabledSchemas: [.flypy], candidateLimit: 5)
        let liveSession = try liveService.makeSession()
        liveSession.simulate(sequence: "zz")
        _ = try liveSession.readSnapshot()
        document.entries[0].text = "实时更新词组"
        try store.save(document)
        try liveService.reloadCustomWords()
        liveSession.refreshCandidates()
        let liveSnapshot = try liveSession.readSnapshot()
        precondition(liveSnapshot.composition?.text == "zz")
        precondition(liveSnapshot.menu.candidates.first?.text == "实时更新词组")
        try store.save(.empty)
        try liveService.reloadCustomWords()
        liveSession.refreshCandidates()
        try check(!liveSession.readSnapshot().menu.candidates.contains { $0.text == "实时更新词组" })
        document.entries[0].text = "修改后的专属词组"
        // Exercise the reported four-key code against the actual iOS dictionary.
        document.entries[0].code = "sdiy"
        try store.save(document)
        let session = try InputService(paths: paths, enabledSchemas: [.flypy], candidateLimit: 5).makeSession()
        session.simulate(sequence: "sdiy")
        let snapshot = try session.readSnapshot()
        precondition(snapshot.commitText == "修改后的专属词组"
            || snapshot.menu.candidates.contains { $0.text == "修改后的专属词组" })
        try store.save(.empty)
        try check(!candidates(.flypy, code: "sdiy").contains("修改后的专属词组"))
        print("PASS: persistence, normalization, duplicate rejection, schema isolation, edit and delete")
    }
}

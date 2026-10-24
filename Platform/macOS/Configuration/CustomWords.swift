import Foundation

struct CustomWordEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var code: String
    var weight: Int?

    init(id: UUID = UUID(), text: String, code: String, weight: Int? = nil) {
        self.id = id
        self.text = text
        self.code = code
        self.weight = weight
    }
}

struct CustomWordsDocument: Equatable, Sendable {
    var comments: [String]
    var entries: [CustomWordEntry]

    static let empty = CustomWordsDocument(comments: [], entries: [])
}

enum CustomWordsStoreError: LocalizedError {
    case invalidLine(Int)
    case emptyText(Int)
    case invalidText(Int)
    case invalidCode(Int)
    case invalidWeight(Int)
    case duplicateEntry(Int, Int)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(line):
            "自定义词组文件第 \(line) 行格式不正确。每行应为“词语、编码、可选权重”三列。"
        case let .emptyText(index):
            "第 \(index) 个词条的词语不能为空。"
        case let .invalidText(index):
            "第 \(index) 个词条包含制表符或换行符。"
        case let .invalidCode(index):
            "第 \(index) 个词条的编码只能包含英文字母和撇号。"
        case let .invalidWeight(index):
            "第 \(index) 个词条的权重必须是大于或等于 0 的整数。"
        case let .duplicateEntry(index, firstIndex):
            "第 \(index) 个词条与第 \(firstIndex) 个词条重复。"
        }
    }
}

struct CustomWordsStore: Sendable {
    static let header = "# 词条<Tab>编码<Tab>可选权重"

    let fileURL: URL

    #if !os(iOS)
    static func applicationDefaults() throws -> Self {
        let paths = try InputServicePaths.applicationDefaults()
        return Self(fileURL: paths.userData.appendingPathComponent("custom_words.tsv"))
    }
    #endif

    func load() throws -> CustomWordsDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        var contents = try String(contentsOf: fileURL, encoding: .utf8)
        // Files saved by Windows Notepad can start with a UTF-8 byte order mark.
        if contents.hasPrefix("\u{FEFF}") { contents.removeFirst() }
        var comments = [String]()
        var entries = [CustomWordEntry]()

        for (offset, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            if trimmedLine.hasPrefix("#") || trimmedLine.hasPrefix("-") {
                if trimmedLine != Self.header {
                    comments.append(rawLine)
                }
                continue
            }

            let fields = rawLine.components(separatedBy: "\t")
            guard fields.count == 2 || fields.count == 3 else {
                throw CustomWordsStoreError.invalidLine(lineNumber)
            }

            let weight: Int?
            if fields.count == 3, !fields[2].trimmingCharacters(in: .whitespaces).isEmpty {
                guard let parsedWeight = Int(fields[2].trimmingCharacters(in: .whitespaces)) else {
                    throw CustomWordsStoreError.invalidLine(lineNumber)
                }
                weight = parsedWeight
            } else {
                weight = nil
            }
            entries.append(CustomWordEntry(text: fields[0], code: fields[1], weight: weight))
        }

        return CustomWordsDocument(
            comments: comments,
            entries: try Self.validated(entries)
        )
    }

    @discardableResult
    func save(_ document: CustomWordsDocument) throws -> CustomWordsDocument {
        let normalizedDocument = try Self.normalized(document)
        let contents = try Self.contents(for: normalizedDocument)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return normalizedDocument
    }

    static func normalized(_ document: CustomWordsDocument) throws -> CustomWordsDocument {
        CustomWordsDocument(
            comments: document.comments,
            entries: try validated(document.entries)
        )
    }

    static func contents(for document: CustomWordsDocument) throws -> String {
        let normalizedDocument = try normalized(document)
        var lines = [Self.header]
        lines.append(contentsOf: normalizedDocument.comments.filter { comment in
            let trimmed = comment.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#") || trimmed.hasPrefix("-")
        })
        lines.append(contentsOf: normalizedDocument.entries.map { entry in
            var fields = [entry.text, entry.code]
            if let weight = entry.weight {
                fields.append(String(weight))
            }
            return fields.joined(separator: "\t")
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private static func validated(_ entries: [CustomWordEntry]) throws -> [CustomWordEntry] {
        var firstIndexByKey = [String: Int]()
        return try entries.enumerated().map { offset, entry in
            let index = offset + 1
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = entry.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.isEmpty else {
                throw CustomWordsStoreError.emptyText(index)
            }
            guard !text.contains("\t") && !text.contains("\n") && !text.contains("\r") else {
                throw CustomWordsStoreError.invalidText(index)
            }
            guard !code.isEmpty,
                code.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'") })
            else {
                throw CustomWordsStoreError.invalidCode(index)
            }
            if let weight = entry.weight, weight < 0 {
                throw CustomWordsStoreError.invalidWeight(index)
            }

            let duplicateKey = "\(text)\u{0}\(code)"
            if let firstIndex = firstIndexByKey[duplicateKey] {
                throw CustomWordsStoreError.duplicateEntry(index, firstIndex)
            }
            firstIndexByKey[duplicateKey] = index
            return CustomWordEntry(id: entry.id, text: text, code: code, weight: entry.weight)
        }
    }
}

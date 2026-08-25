#!/usr/bin/env swift

import Foundation

enum GeneratorError: Error, CustomStringConvertible {
    case usage
    case missingDataMarker(String)

    var description: String {
        switch self {
        case .usage:
            "usage: generate-flypy-dictionary.swift <flypydz.dict.yaml> <output> [supplement.txt ...]"
        case .missingDataMarker(let path):
            "dictionary has no data section: \(path)"
        }
    }
}

struct Entry: Hashable {
    let text: String
    let code: String
}

func fields(from line: Substring) -> (String, String)? {
    guard !line.isEmpty, !line.hasPrefix("#") else {
        return nil
    }
    let values = line.split(separator: "\t", omittingEmptySubsequences: false)
    guard values.count >= 2 else {
        return nil
    }
    let text = String(values[0])
    let code = String(values[1]).trimmingCharacters(in: .whitespaces)
    let validCodeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz;'")
    guard !text.isEmpty, !code.isEmpty,
        code.unicodeScalars.allSatisfy(validCodeCharacters.contains)
    else {
        return nil
    }
    return (text, code)
}

func dataLines(at path: String, requiresMarker: Bool) throws -> ArraySlice<Substring> {
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    guard requiresMarker else {
        return lines[...]
    }
    guard let marker = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "..." }) else {
        throw GeneratorError.missingDataMarker(path)
    }
    return lines[lines.index(after: marker)...]
}

do {
    guard CommandLine.arguments.count >= 3 else {
        throw GeneratorError.usage
    }
    let reverseDictionaryPath = CommandLine.arguments[1]
    let outputPath = CommandLine.arguments[2]
    let supplementPaths = Array(CommandLine.arguments.dropFirst(3))

    var entries = [Entry]()
    var seen = Set<Entry>()
    func append(_ entry: Entry) {
        if seen.insert(entry).inserted {
            entries.append(entry)
        }
    }

    // Preserve the user's curated short codes and phrase ordering first.
    for path in supplementPaths {
        for line in try dataLines(at: path, requiresMarker: false) {
            guard let (text, code) = fields(from: line), code.count <= 4 else {
                continue
            }
            append(Entry(text: text, code: code))
        }
    }

    // flypydz stores the canonical 小鹤 four-key code: two phonetic keys and
    // two shape keys. Add exact two- and three-key entries so each shape key
    // progressively narrows candidates without relying on table completion.
    for line in try dataLines(at: reverseDictionaryPath, requiresMarker: true) {
        guard let (text, code) = fields(from: line) else {
            continue
        }
        if code.count >= 2 {
            append(Entry(text: text, code: String(code.prefix(2))))
        }
        if code.count >= 3 {
            append(Entry(text: text, code: String(code.prefix(3))))
        }
        append(Entry(text: text, code: code))
    }

    let header = """
    # encoding: utf-8
    # Generated from the user's existing 小鹤音形 configuration.
    # Code = 小鹤双拼两键 + optional first/second 小鹤形码.
    # Do not edit this generated file directly.

    ---
    name: flypy
    version: "10.26.2-fengyu.1"
    sort: original
    use_preset_vocabulary: false
    ...

    """
    let body = entries.map { "\($0.text)\t\($0.code)" }.joined(separator: "\n")
    try (header + body + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("generatedRows=\(entries.count)")
} catch {
    fputs("generate-flypy-dictionary: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

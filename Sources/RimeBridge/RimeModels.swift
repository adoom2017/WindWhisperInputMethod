import Foundation

struct RimeCandidateSnapshot: Equatable, Sendable {
    let text: String
    let comment: String?
}

struct RimeCompositionSnapshot: Equatable, Sendable {
    let text: String
    let selectionRange: NSRange
    let cursorPosition: Int
}

struct RimeMenuSnapshot: Equatable, Sendable {
    let pageSize: Int
    let pageNumber: Int
    let isLastPage: Bool
    let highlightedIndex: Int
    let candidates: [RimeCandidateSnapshot]
}

struct RimeStatusSnapshot: Equatable, Sendable {
    let schemaIdentifier: String?
    let schemaName: String?
    let isComposing: Bool
    let isASCIIMode: Bool
    let isDisabled: Bool
}

struct RimeSnapshot: Equatable, Sendable {
    let commitText: String?
    let composition: RimeCompositionSnapshot?
    let menu: RimeMenuSnapshot
    let status: RimeStatusSnapshot
}

enum RimeRangeConverter {
    static func utf16Offset(forUTF8Offset offset: Int, in text: String) -> Int? {
        guard offset >= 0 else {
            return nil
        }
        let utf8 = text.utf8
        guard
            let utf8Index = utf8.index(
                utf8.startIndex,
                offsetBy: offset,
                limitedBy: utf8.endIndex
            ), let stringIndex = String.Index(utf8Index, within: text)
        else {
            return nil
        }
        return text.utf16.distance(from: text.utf16.startIndex, to: stringIndex)
    }

    static func utf16Range(
        startUTF8Offset: Int,
        endUTF8Offset: Int,
        in text: String
    ) -> NSRange? {
        guard
            let start = utf16Offset(forUTF8Offset: startUTF8Offset, in: text),
            let end = utf16Offset(forUTF8Offset: endUTF8Offset, in: text),
            end >= start
        else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }
}

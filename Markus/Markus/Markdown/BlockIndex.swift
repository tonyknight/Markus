import Foundation

nonisolated struct FoldID: Hashable, Sendable, Codable {
    /// Profile-defined fold kind. Encoded as a single JSON string so
    /// v1.2 records (`"heading"`, `"fence"`) still load. Later profiles
    /// add their own raw values (e.g. JSON object/array).
    struct Kind: Hashable, Sendable, Codable, RawRepresentable {
        var rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        static let heading = Kind(rawValue: "heading")
        static let fence = Kind(rawValue: "fence")
        static let object = Kind(rawValue: "object")
        static let array = Kind(rawValue: "array")

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(String.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    var kind: Kind
    var startLine: Int
    /// A short digest of the block's opening line content, used to
    /// re-match a fold to the same logical block after the block index
    /// rebuilds and `startLine` shifts (R17).
    var anchor: String
}

/// A short, stable digest of a single line of text — deliberately not
/// cryptographic, just enough entropy to re-identify a block's opening
/// line across a block-index rebuild.
nonisolated enum FoldAnchor {
    static func digest(_ line: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in line.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

nonisolated struct Block: Equatable, Sendable {
    var id: FoldID
    var kind: MarkdownBlockKind
    var bytes: Range<Int>
    var lines: Range<Int>
    var foldExtent: Range<Int>?
}

nonisolated enum BlockIndex: Sendable {
    static func build(markdown: String) -> [Block] {
        let parsed = MarkdownParser().parse(markdown)
        let foldable = parsed.filter { block in
            switch block.kind {
            case .heading, .fencedCode:
                return true
            case .other:
                return false
            }
        }

        // Built once and shared by every block (P5) — also needed by every
        // block, not just fences, to read the opening line for the anchor.
        let sourceMap = SourceMap(markdown: markdown)

        return foldable.enumerated().map { index, parsedBlock in
            let foldExtent: Range<Int>?
            let foldKind: FoldID.Kind
            switch parsedBlock.kind {
            case .heading(let level):
                foldKind = .heading
                let next = foldable[(index + 1)...].first { candidate in
                    if case .heading(let candidateLevel) = candidate.kind {
                        return candidateLevel <= level
                    }
                    return false
                }
                let upper = next?.bytes.lowerBound ?? markdown.utf8.count
                let proposed = parsedBlock.bytes.upperBound..<upper
                foldExtent = proposed.isEmpty ? nil : proposed
            case .fencedCode:
                foldKind = .fence
                let openerEnd = sourceMap.endOffset(ofLine: parsedBlock.lines.lowerBound)
                let proposed = openerEnd..<parsedBlock.bytes.upperBound
                foldExtent = proposed.isEmpty ? nil : proposed
            case .other:
                preconditionFailure("filtered out")
            }

            let anchor = FoldAnchor.digest(openingLineText(markdown: markdown, sourceMap: sourceMap, line: parsedBlock.lines.lowerBound))

            return Block(
                id: FoldID(kind: foldKind, startLine: parsedBlock.lines.lowerBound, anchor: anchor),
                kind: parsedBlock.kind,
                bytes: parsedBlock.bytes,
                lines: parsedBlock.lines,
                foldExtent: foldExtent
            )
        }
    }

    private static func openingLineText(markdown: String, sourceMap: SourceMap, line: Int) -> String {
        let bytes = sourceMap.offset(ofLine: line)..<sourceMap.endOffset(ofLine: line)
        let scalars = Array(markdown.utf8)[bytes]
        return String(decoding: scalars, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}

struct SourceMap: Sendable {
    /// Test-only instrumentation (T04/P5): a reference-type counter of
    /// `SourceMap` constructions, bound per-call-tree via the
    /// `@TaskLocal` below rather than shared as a bare global. A bare
    /// global counter is contaminated by Swift Testing's parallel test
    /// execution — unrelated tests construct `SourceMap`s on their own
    /// concurrently-running tasks throughout a full suite run, and a
    /// process-wide `static var` cannot tell those apart from the
    /// construction this specific test is trying to count. Binding a
    /// counter via `withValue(_:operation:)` scopes visibility to the
    /// dynamic extent of that call (this test's own synchronous call
    /// into `BlockIndex.build`), so concurrently-running unrelated
    /// tests — which never bind `constructionCounter` — simply no-op
    /// against a `nil` task-local and cannot inflate the count.
    final class ConstructionCounter: @unchecked Sendable {
        private(set) var value = 0
        func increment() { value += 1 }
    }
    @TaskLocal static var constructionCounter: ConstructionCounter?

    let lineStarts: [Int]
    let byteCount: Int

    init(markdown: String) {
        SourceMap.constructionCounter?.increment()
        let bytes = Array(markdown.utf8)
        byteCount = bytes.count
        var starts = [0]
        for (index, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") {
            starts.append(index + 1)
        }
        lineStarts = starts
    }

    func byteRange(startLine: Int, endLine: Int) -> Range<Int> {
        let lower = offset(ofLine: startLine)
        let upper = endOffset(ofLine: endLine)
        return lower..<upper
    }

    func offset(ofLine line: Int) -> Int {
        lineStarts[line - 1]
    }

    func endOffset(ofLine line: Int) -> Int {
        if line < lineStarts.count {
            return lineStarts[line]
        }
        return byteCount
    }

    /// cmark sourcepos columns are 1-based and inclusive, counted in UTF-8 bytes.
    func byteRange(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) -> Range<Int> {
        let lower = min(byteCount, offset(ofLine: startLine) + startColumn - 1)
        let upper = min(byteCount, offset(ofLine: endLine) + endColumn)
        return lower..<max(lower, upper)
    }

    func lineRange(startLine: Int, endLine: Int) -> Range<Int> {
        startLine..<(endLine + 1)
    }
}

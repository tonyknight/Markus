import Foundation

nonisolated struct FoldID: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case heading
        case fence
    }

    var kind: Kind
    var startLine: Int
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
                let openerEnd = SourceMap(markdown: markdown).endOffset(ofLine: parsedBlock.lines.lowerBound)
                let proposed = openerEnd..<parsedBlock.bytes.upperBound
                foldExtent = proposed.isEmpty ? nil : proposed
            case .other:
                preconditionFailure("filtered out")
            }

            return Block(
                id: FoldID(kind: foldKind, startLine: parsedBlock.lines.lowerBound),
                kind: parsedBlock.kind,
                bytes: parsedBlock.bytes,
                lines: parsedBlock.lines,
                foldExtent: foldExtent
            )
        }
    }
}

struct SourceMap: Sendable {
    let lineStarts: [Int]
    let byteCount: Int

    init(markdown: String) {
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

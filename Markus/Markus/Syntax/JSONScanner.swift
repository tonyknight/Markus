import Foundation

/// Bounds for a JSON scan so a multi-MB buffer cannot freeze typing (N2).
/// The JSON profile uses `default`; callers that need a full pass pass `unbounded`.
struct JSONScanBudget: Sendable {
    var maxBytes: Int
    var maxFoldables: Int
    var maxOutlineRows: Int
    var maxHighlightSpans: Int
    var timeLimitNanoseconds: UInt64?

    static let unbounded = JSONScanBudget(
        maxBytes: Int.max,
        maxFoldables: Int.max,
        maxOutlineRows: Int.max,
        maxHighlightSpans: Int.max,
        timeLimitNanoseconds: nil
    )

    /// Prefix + foldable/span caps + 50 ms, same spirit as v1.1 span budgets.
    static let `default` = JSONScanBudget(
        maxBytes: 2_097_152,
        maxFoldables: 4_096,
        maxOutlineRows: 2_048,
        maxHighlightSpans: 4_096,
        timeLimitNanoseconds: 50_000_000
    )
}

struct JSONScanResult: Equatable, Sendable {
    var foldables: [Block]
    var outlineRows: [OutlineItem]
    var diagnostics: [ParseDiagnostic]
    var highlightSpans: [HighlightSpan]
}

/// Dedicated JSON scanner. Tracks UTF-8 offsets so object/array folds have
/// real byte ranges. `JSONSerialization` can validate but does not yield
/// fold extents, so it is not used here.
enum JSONScanner {
    static func scan(_ buffer: String, budget: JSONScanBudget = .unbounded) -> JSONScanResult {
        var scanner = Engine(buffer: buffer, budget: budget)
        scanner.run()
        return scanner.result()
    }
}

private struct Engine {
    let bytes: [UInt8]
    let budget: JSONScanBudget
    let scanEnd: Int
    let started: DispatchTime

    var i = 0
    var line = 1
    var lineStart = 0
    var lineStarts: [Int] = [0]
    var truncated = false

    var foldables: [Block] = []
    var outlineRows: [OutlineItem] = []
    var diagnostics: [ParseDiagnostic] = []
    var highlightSpans: [HighlightSpan] = []

    init(buffer: String, budget: JSONScanBudget) {
        bytes = Array(buffer.utf8)
        self.budget = budget
        scanEnd = min(bytes.count, budget.maxBytes)
        started = .now()
    }

    func result() -> JSONScanResult {
        JSONScanResult(
            foldables: foldables,
            outlineRows: outlineRows,
            diagnostics: diagnostics,
            highlightSpans: highlightSpans
        )
    }

    mutating func run() {
        skipBOM()
        skipWhitespace()
        if atEnd {
            addDiagnostic(line: line, message: "Expected a JSON value", severity: .error)
            return
        }
        _ = parseValue(level: 0)
        skipWhitespace()
        if truncated { return }
        if i < scanEnd {
            addDiagnostic(line: line, message: "Unexpected data after top-level value", severity: .error)
        } else if scanEnd < bytes.count {
            markTruncated()
        }
    }

    private var atEnd: Bool {
        i >= scanEnd || i >= bytes.count
    }

    private var peek: UInt8? {
        guard !atEnd else { return nil }
        return bytes[i]
    }

    mutating func skipBOM() {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            i = 3
        }
    }

    mutating func skipWhitespace() {
        while let b = peek {
            switch b {
            case 0x20, 0x09, 0x0D:
                i += 1
            case 0x0A:
                i += 1
                line += 1
                lineStart = i
                lineStarts.append(i)
            default:
                return
            }
        }
    }

    mutating func parseValue(level: Int) -> Bool {
        if isOverBudget() { return false }
        skipWhitespace()
        guard let b = peek else {
            addDiagnostic(line: line, message: "Expected a JSON value", severity: .error)
            return false
        }
        switch b {
        case UInt8(ascii: "{"):
            return parseObject(level: level)
        case UInt8(ascii: "["):
            return parseArray(level: level)
        case UInt8(ascii: "\""):
            return parseString(highlight: true) != nil
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return parseNumber()
        case UInt8(ascii: "t"):
            return parseLiteral("true")
        case UInt8(ascii: "f"):
            return parseLiteral("false")
        case UInt8(ascii: "n"):
            return parseLiteral("null")
        default:
            addDiagnostic(line: line, message: "Unexpected character in JSON", severity: .error)
            i += 1
            return false
        }
    }

    mutating func parseObject(level: Int) -> Bool {
        let openerOffset = i
        let openerLine = line
        let openerLineStart = lineStart
        i += 1
        skipWhitespace()
        if peek == UInt8(ascii: "}") {
            i += 1
            finishContainer(kind: .object, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
            return true
        }
        while !atEnd && !truncated {
            skipWhitespace()
            guard peek == UInt8(ascii: "\"") else {
                addDiagnostic(line: line, message: "Expected object key", severity: .error)
                recoverToObjectBoundary()
                if peek == UInt8(ascii: ",") {
                    i += 1
                    continue
                }
                break
            }
            let keyLine = line
            guard let keyRange = parseString(highlight: true) else {
                recoverToObjectBoundary()
                if peek == UInt8(ascii: ",") {
                    i += 1
                    continue
                }
                break
            }
            addOutlineRow(title: stringInterior(keyRange), sourceLine: keyLine, level: level)
            skipWhitespace()
            guard peek == UInt8(ascii: ":") else {
                addDiagnostic(line: line, message: "Expected ':' after object key", severity: .error)
                recoverToObjectBoundary()
                if peek == UInt8(ascii: ",") {
                    i += 1
                    continue
                }
                break
            }
            i += 1
            skipWhitespace()
            _ = parseValue(level: level + 1)
            skipWhitespace()
            if peek == UInt8(ascii: "}") {
                i += 1
                finishContainer(kind: .object, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
                return true
            }
            if peek == UInt8(ascii: ",") {
                i += 1
                skipWhitespace()
                if peek == UInt8(ascii: "}") {
                    addDiagnostic(line: line, message: "Trailing comma in object", severity: .error)
                    i += 1
                    finishContainer(kind: .object, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
                    return true
                }
                continue
            }
            addDiagnostic(line: line, message: "Expected ',' or '}' in object", severity: .error)
            recoverToObjectBoundary()
            if peek == UInt8(ascii: "}") {
                i += 1
                finishContainer(kind: .object, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
                return true
            }
            if peek == UInt8(ascii: ",") {
                i += 1
                continue
            }
            break
        }
        addDiagnostic(line: openerLine, message: "Unclosed object", severity: .error)
        return false
    }

    mutating func parseArray(level: Int) -> Bool {
        let openerOffset = i
        let openerLine = line
        let openerLineStart = lineStart
        i += 1
        skipWhitespace()
        if peek == UInt8(ascii: "]") {
            i += 1
            finishContainer(kind: .array, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
            return true
        }
        var index = 0
        while !atEnd && !truncated {
            skipWhitespace()
            if peek == UInt8(ascii: "{") || peek == UInt8(ascii: "[") {
                addOutlineRow(title: "[\(index)]", sourceLine: line, level: level)
            }
            _ = parseValue(level: level + 1)
            index += 1
            skipWhitespace()
            if peek == UInt8(ascii: "]") {
                i += 1
                finishContainer(kind: .array, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
                return true
            }
            if peek == UInt8(ascii: ",") {
                i += 1
                skipWhitespace()
                if peek == UInt8(ascii: "]") {
                    addDiagnostic(line: line, message: "Trailing comma in array", severity: .error)
                    i += 1
                    finishContainer(kind: .array, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
                    return true
                }
                continue
            }
            addDiagnostic(line: line, message: "Expected ',' or ']' in array", severity: .error)
            recoverToArrayBoundary()
            if peek == UInt8(ascii: "]") {
                i += 1
                finishContainer(kind: .array, openerOffset: openerOffset, openerLine: openerLine, openerLineStart: openerLineStart)
                return true
            }
            if peek == UInt8(ascii: ",") {
                i += 1
                continue
            }
            break
        }
        addDiagnostic(line: openerLine, message: "Unclosed array", severity: .error)
        return false
    }

    mutating func parseString(highlight: Bool) -> Range<Int>? {
        guard peek == UInt8(ascii: "\"") else { return nil }
        let start = i
        i += 1
        while let b = peek {
            if b == UInt8(ascii: "\"") {
                i += 1
                let range = start..<i
                if highlight { addHighlight(range, role: .string) }
                return range
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                guard peek != nil else { break }
                if peek == UInt8(ascii: "u") {
                    i += 1
                    for _ in 0..<4 {
                        guard let h = peek, isHex(h) else {
                            addDiagnostic(line: line, message: "Invalid Unicode escape in string", severity: .error)
                            break
                        }
                        i += 1
                    }
                } else {
                    i += 1
                }
                continue
            }
            if b == 0x0A {
                i += 1
                line += 1
                lineStart = i
                lineStarts.append(i)
                continue
            }
            i += 1
        }
        addDiagnostic(line: line, message: "Unclosed string", severity: .error)
        return nil
    }

    mutating func parseNumber() -> Bool {
        let start = i
        if peek == UInt8(ascii: "-") { i += 1 }
        guard let first = peek, isDigit(first) else {
            addDiagnostic(line: line, message: "Invalid number", severity: .error)
            return false
        }
        if first == UInt8(ascii: "0") {
            i += 1
            if let next = peek, isDigit(next) {
                addDiagnostic(line: line, message: "Invalid leading zero in number", severity: .error)
                while let b = peek, isDigit(b) { i += 1 }
            }
        } else {
            while let b = peek, isDigit(b) { i += 1 }
        }
        if peek == UInt8(ascii: ".") {
            i += 1
            guard let b = peek, isDigit(b) else {
                addDiagnostic(line: line, message: "Invalid number fraction", severity: .error)
                addHighlight(start..<i, role: .number)
                return false
            }
            while let d = peek, isDigit(d) { i += 1 }
        }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            i += 1
            if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { i += 1 }
            guard let b = peek, isDigit(b) else {
                addDiagnostic(line: line, message: "Invalid number exponent", severity: .error)
                addHighlight(start..<i, role: .number)
                return false
            }
            while let d = peek, isDigit(d) { i += 1 }
        }
        addHighlight(start..<i, role: .number)
        return true
    }

    mutating func parseLiteral(_ word: String) -> Bool {
        let needle = Array(word.utf8)
        guard i + needle.count <= scanEnd else {
            addDiagnostic(line: line, message: "Unexpected character in JSON", severity: .error)
            i += 1
            return false
        }
        for offset in needle.indices {
            if bytes[i + offset] != needle[offset] {
                addDiagnostic(line: line, message: "Unexpected character in JSON", severity: .error)
                i += 1
                return false
            }
        }
        let after = i + needle.count
        if after < scanEnd {
            let next = bytes[after]
            if isAlpha(next) || isDigit(next) {
                addDiagnostic(line: line, message: "Unexpected character in JSON", severity: .error)
                i += 1
                return false
            }
        }
        let range = i..<after
        i = after
        addHighlight(range, role: .keyword)
        return true
    }

    mutating func finishContainer(
        kind: FoldID.Kind,
        openerOffset: Int,
        openerLine: Int,
        openerLineStart: Int
    ) {
        let closerEnd = i
        let openerEnd = endOffset(ofLine: openerLine)
        let proposed = openerEnd..<closerEnd
        guard !proposed.isEmpty, openerEnd < closerEnd else { return }
        guard foldables.count < budget.maxFoldables else {
            markTruncated()
            return
        }
        let opening = openingLineText(start: openerLineStart, line: openerLine)
        let column = openerOffset - openerLineStart
        let anchor = FoldAnchor.digest("\(opening)\n\(column)")
        let closerLine = max(openerLine, line)
        foldables.append(Block(
            id: FoldID(kind: kind, startLine: openerLine, anchor: anchor),
            kind: .other,
            bytes: openerOffset..<closerEnd,
            lines: openerLine..<(closerLine + 1),
            foldExtent: proposed
        ))
    }

    mutating func recoverToObjectBoundary() {
        while let b = peek {
            if b == UInt8(ascii: "}") || b == UInt8(ascii: ",") { return }
            if b == UInt8(ascii: "\"") {
                _ = parseString(highlight: false)
                continue
            }
            advanceOne()
        }
    }

    mutating func recoverToArrayBoundary() {
        while let b = peek {
            if b == UInt8(ascii: "]") || b == UInt8(ascii: ",") { return }
            if b == UInt8(ascii: "\"") {
                _ = parseString(highlight: false)
                continue
            }
            advanceOne()
        }
    }

    mutating func advanceOne() {
        guard let b = peek else { return }
        if b == 0x0A {
            i += 1
            line += 1
            lineStart = i
            lineStarts.append(i)
        } else {
            i += 1
        }
    }

    func endOffset(ofLine target: Int) -> Int {
        if target < lineStarts.count {
            return lineStarts[target]
        }
        return scanEnd < bytes.count ? scanEnd : bytes.count
    }

    func openingLineText(start: Int, line: Int) -> String {
        let end = min(endOffset(ofLine: line), bytes.count)
        guard start < end else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    func stringInterior(_ range: Range<Int>) -> String {
        let innerStart = range.lowerBound + 1
        let innerEnd = max(innerStart, range.upperBound - 1)
        guard innerStart < innerEnd, innerEnd <= bytes.count else { return "" }
        return String(decoding: bytes[innerStart..<innerEnd], as: UTF8.self)
    }

    mutating func addOutlineRow(title: String, sourceLine: Int, level: Int) {
        guard outlineRows.count < budget.maxOutlineRows else { return }
        outlineRows.append(OutlineItem(title: title, sourceLine: sourceLine, level: level))
    }

    mutating func addHighlight(_ range: Range<Int>, role: HighlightSpan.Role) {
        guard highlightSpans.count < budget.maxHighlightSpans else { return }
        guard !range.isEmpty else { return }
        highlightSpans.append(HighlightSpan(bytes: range, role: role))
    }

    mutating func addDiagnostic(line: Int, message: String, severity: ParseDiagnostic.Severity) {
        guard diagnostics.count < 16 else { return }
        diagnostics.append(ParseDiagnostic(line: line, message: message, severity: severity))
    }

    mutating func isOverBudget() -> Bool {
        if truncated { return true }
        if let limit = budget.timeLimitNanoseconds {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- started.uptimeNanoseconds
            if elapsed > limit {
                markTruncated()
                return true
            }
        }
        if i >= scanEnd, scanEnd < bytes.count {
            markTruncated()
            return true
        }
        if foldables.count >= budget.maxFoldables {
            markTruncated()
            return true
        }
        return false
    }

    mutating func markTruncated() {
        guard !truncated else { return }
        truncated = true
        addDiagnostic(
            line: line,
            message: "JSON scan stopped at size or time budget",
            severity: .warning
        )
    }
}

private func isDigit(_ b: UInt8) -> Bool {
    b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")
}

private func isHex(_ b: UInt8) -> Bool {
    isDigit(b)
        || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "f"))
        || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "F"))
}

private func isAlpha(_ b: UInt8) -> Bool {
    (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
}

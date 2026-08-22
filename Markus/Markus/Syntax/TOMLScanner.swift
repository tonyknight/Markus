import Foundation

/// Bounds for a TOML scan so a multi-MB buffer cannot freeze typing (N2).
/// The TOML profile uses `default`; callers that need a full pass pass `unbounded`.
struct TOMLScanBudget: Sendable {
    var maxBytes: Int
    var maxFoldables: Int
    var maxOutlineRows: Int
    var maxHighlightSpans: Int
    var timeLimitNanoseconds: UInt64?

    static let unbounded = TOMLScanBudget(
        maxBytes: Int.max,
        maxFoldables: Int.max,
        maxOutlineRows: Int.max,
        maxHighlightSpans: Int.max,
        timeLimitNanoseconds: nil
    )

    /// Prefix + foldable/span caps + 50 ms, same spirit as `JSONScanBudget`.
    static let `default` = TOMLScanBudget(
        maxBytes: 2_097_152,
        maxFoldables: 4_096,
        maxOutlineRows: 2_048,
        maxHighlightSpans: 4_096,
        timeLimitNanoseconds: 50_000_000
    )
}

struct TOMLScanResult: Equatable, Sendable {
    var foldables: [Block]
    var outlineRows: [OutlineItem]
    var diagnostics: [ParseDiagnostic]
    var highlightSpans: [HighlightSpan]
}

/// TOML scanner. Tables `[name]` and array-of-tables `[[name]]` fold from
/// after the header line through the last line before the next header (or
/// EOF). Inline `{…}` / `[…]` values are parsed so they are not mistaken
/// for headers. `Block.kind` is `.other` so Markdown Preview substitution
/// never treats these as fences.
enum TOMLScanner {
    static func scan(_ buffer: String, budget: TOMLScanBudget = .unbounded) -> TOMLScanResult {
        var scanner = Engine(buffer: buffer, budget: budget)
        scanner.run()
        return scanner.result()
    }
}

private struct TableHeader {
    var kind: FoldID.Kind
    var openerOffset: Int
    var openerLine: Int
    var openerLineStart: Int
    var title: String
    var level: Int
}

private struct Engine {
    let bytes: [UInt8]
    let budget: TOMLScanBudget
    let scanEnd: Int
    let started: DispatchTime

    var i = 0
    var line = 1
    var lineStart = 0
    var lineStarts: [Int] = [0]
    var truncated = false

    var headers: [TableHeader] = []
    var foldables: [Block] = []
    var outlineRows: [OutlineItem] = []
    var diagnostics: [ParseDiagnostic] = []
    var highlightSpans: [HighlightSpan] = []

    init(buffer: String, budget: TOMLScanBudget) {
        bytes = Array(buffer.utf8)
        self.budget = budget
        scanEnd = min(bytes.count, budget.maxBytes)
        started = .now()
    }

    func result() -> TOMLScanResult {
        TOMLScanResult(
            foldables: foldables,
            outlineRows: outlineRows,
            diagnostics: diagnostics,
            highlightSpans: highlightSpans
        )
    }

    mutating func run() {
        skipBOM()
        while !atEnd && !truncated {
            if isOverBudget() { break }
            skipLineSpace()
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            if peek == UInt8(ascii: "#") {
                skipComment()
                continue
            }
            if peek == UInt8(ascii: "[") {
                parseTableHeader()
            } else {
                parseKeyval()
            }
        }
        finishTables()
        if truncated { return }
        if scanEnd < bytes.count {
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

    private func peek(at offset: Int) -> UInt8? {
        let index = i + offset
        guard index < scanEnd, index < bytes.count else { return nil }
        return bytes[index]
    }

    mutating func skipBOM() {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            i = 3
        }
    }

    mutating func parseTableHeader() {
        let openerOffset = i
        let openerLine = line
        let openerLineStart = lineStart
        let isArrayTable = peek(at: 1) == UInt8(ascii: "[")
        i += isArrayTable ? 2 : 1
        skipLineSpace()
        let segments = parseKey(highlight: true)
        skipLineSpace()
        let closed: Bool
        if isArrayTable {
            closed = peek == UInt8(ascii: "]") && peek(at: 1) == UInt8(ascii: "]")
            if closed { i += 2 }
        } else {
            closed = peek == UInt8(ascii: "]")
            if closed { i += 1 }
        }
        if !closed {
            addDiagnostic(line: openerLine, message: "Malformed table header", severity: .error)
            skipToNewline()
            return
        }
        let title = decode(openerOffset..<i).trimmingCharacters(in: .whitespaces)
        let kind: FoldID.Kind = isArrayTable ? .arrayTable : .table
        let level = max(0, segments - 1)
        guard headers.count < budget.maxFoldables else {
            markTruncated()
            skipToNewline()
            return
        }
        headers.append(TableHeader(
            kind: kind,
            openerOffset: openerOffset,
            openerLine: openerLine,
            openerLineStart: openerLineStart,
            title: title,
            level: level
        ))
        addOutlineRow(title: title, sourceLine: openerLine, level: level)
        skipLineSpace()
        if peek == UInt8(ascii: "#") {
            skipComment()
        } else if let b = peek, b != 0x0A {
            addDiagnostic(line: line, message: "Unexpected data after table header", severity: .error)
            skipToNewline()
        }
    }

    mutating func parseKeyval() {
        _ = parseKey(highlight: true)
        skipLineSpace()
        guard peek == UInt8(ascii: "=") else {
            addDiagnostic(line: line, message: "Expected '=' after key", severity: .error)
            skipToNewline()
            return
        }
        i += 1
        skipLineSpace()
        _ = parseValue()
        skipLineSpace()
        if peek == UInt8(ascii: "#") {
            skipComment()
        } else if let b = peek, b != 0x0A {
            addDiagnostic(line: line, message: "Unexpected data after value", severity: .error)
            skipToNewline()
        }
    }

    /// Returns the number of dotted-key segments (1 for a single key).
    mutating func parseKey(highlight: Bool) -> Int {
        var segments = 0
        while !atEnd && !truncated {
            skipLineSpace()
            let start = i
            if peek == UInt8(ascii: "\"") || peek == UInt8(ascii: "'") {
                _ = parseString(allowMultiline: false)
            } else if parseBareKey() {
                if highlight { addHighlight(start..<i, role: .keyword) }
            } else {
                if segments == 0 {
                    addDiagnostic(line: line, message: "Expected a key", severity: .error)
                }
                break
            }
            segments += 1
            skipLineSpace()
            if peek == UInt8(ascii: ".") {
                i += 1
                continue
            }
            break
        }
        return max(segments, 1)
    }

    mutating func parseBareKey() -> Bool {
        guard let first = peek, isBareKeyChar(first) else { return false }
        while let b = peek, isBareKeyChar(b) {
            i += 1
        }
        return true
    }

    mutating func parseValue() -> Bool {
        if isOverBudget() { return false }
        skipLineSpace()
        guard let b = peek else {
            addDiagnostic(line: line, message: "Expected a value", severity: .error)
            return false
        }
        switch b {
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return parseString(allowMultiline: true) != nil
        case UInt8(ascii: "["):
            return parseArray()
        case UInt8(ascii: "{"):
            return parseInlineTable()
        default:
            return parseAtomicValue()
        }
    }

    mutating func parseArray() -> Bool {
        let openerLine = line
        i += 1
        while !atEnd && !truncated {
            if isOverBudget() { return false }
            skipSpaceCommentsAndNewlines()
            if peek == UInt8(ascii: "]") {
                i += 1
                return true
            }
            guard parseValue() else {
                recoverToArrayEnd()
                if peek == UInt8(ascii: "]") { i += 1 }
                return false
            }
            skipSpaceCommentsAndNewlines()
            if peek == UInt8(ascii: ",") {
                i += 1
                continue
            }
            if peek == UInt8(ascii: "]") {
                i += 1
                return true
            }
            addDiagnostic(line: line, message: "Expected ',' or ']' in array", severity: .error)
            recoverToArrayEnd()
            if peek == UInt8(ascii: "]") { i += 1 }
            return false
        }
        addDiagnostic(line: openerLine, message: "Unclosed array", severity: .error)
        return false
    }

    mutating func parseInlineTable() -> Bool {
        let openerLine = line
        i += 1
        skipLineSpace()
        if peek == UInt8(ascii: "}") {
            i += 1
            return true
        }
        while !atEnd && !truncated {
            if isOverBudget() { return false }
            skipLineSpace()
            if peek == 0x0A {
                addDiagnostic(line: line, message: "Newline in inline table", severity: .error)
                return false
            }
            if peek == UInt8(ascii: "}") {
                i += 1
                return true
            }
            _ = parseKey(highlight: true)
            skipLineSpace()
            guard peek == UInt8(ascii: "=") else {
                addDiagnostic(line: line, message: "Expected '=' in inline table", severity: .error)
                recoverToInlineTableEnd()
                if peek == UInt8(ascii: "}") { i += 1 }
                return false
            }
            i += 1
            skipLineSpace()
            _ = parseValue()
            skipLineSpace()
            if peek == UInt8(ascii: ",") {
                i += 1
                skipLineSpace()
                continue
            }
            if peek == UInt8(ascii: "}") {
                i += 1
                return true
            }
            addDiagnostic(line: line, message: "Expected ',' or '}' in inline table", severity: .error)
            recoverToInlineTableEnd()
            if peek == UInt8(ascii: "}") { i += 1 }
            return false
        }
        addDiagnostic(line: openerLine, message: "Unclosed inline table", severity: .error)
        return false
    }

    mutating func parseString(allowMultiline: Bool) -> Range<Int>? {
        guard let quote = peek, quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") else {
            return nil
        }
        let isLiteral = quote == UInt8(ascii: "'")
        if allowMultiline,
           peek(at: 1) == quote,
           peek(at: 2) == quote {
            return parseMultilineString(quote: quote, isLiteral: isLiteral)
        }
        return parseOneLineString(quote: quote, isLiteral: isLiteral)
    }

    mutating func parseOneLineString(quote: UInt8, isLiteral: Bool) -> Range<Int>? {
        let start = i
        let startLine = line
        i += 1
        while let b = peek {
            if b == quote {
                i += 1
                addHighlight(start..<i, role: .string)
                return start..<i
            }
            if b == 0x0A {
                addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
                addHighlight(start..<i, role: .string)
                return nil
            }
            if !isLiteral, b == UInt8(ascii: "\\") {
                i += 1
                guard peek != nil else { break }
                i += 1
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
        return nil
    }

    mutating func parseMultilineString(quote: UInt8, isLiteral: Bool) -> Range<Int>? {
        let start = i
        let startLine = line
        i += 3
        if peek == 0x0A {
            consumeNewline()
        }
        while !atEnd {
            if peek == quote, peek(at: 1) == quote, peek(at: 2) == quote {
                i += 3
                while peek == quote {
                    i += 1
                }
                addHighlight(start..<i, role: .string)
                return start..<i
            }
            if !isLiteral, peek == UInt8(ascii: "\\") {
                i += 1
                if peek == 0x0A {
                    consumeNewline()
                    continue
                }
                if peek != nil { i += 1 }
                continue
            }
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
        return nil
    }

    mutating func parseAtomicValue() -> Bool {
        skipLineSpace()
        guard peek != nil else {
            addDiagnostic(line: line, message: "Expected a value", severity: .error)
            return false
        }
        let start = i
        if hasKeyword("true") || hasKeyword("false") {
            consumeKeyword()
            addHighlight(start..<i, role: .keyword)
            return true
        }
        if hasKeyword("inf") || hasKeyword("nan") {
            consumeKeyword()
            addHighlight(start..<i, role: .number)
            return true
        }
        if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") {
            i += 1
            if hasKeyword("inf") || hasKeyword("nan") {
                consumeKeyword()
                addHighlight(start..<i, role: .number)
                return true
            }
        }
        while let b = peek, isAtomicValueChar(b) {
            i += 1
        }
        if start == i {
            addDiagnostic(line: line, message: "Expected a value", severity: .error)
            i += 1
            return false
        }
        addHighlight(start..<i, role: .number)
        return true
    }

    mutating func consumeKeyword() {
        while let b = peek, isBareKeyChar(b) {
            i += 1
        }
    }

    func hasKeyword(_ word: String) -> Bool {
        let needle = Array(word.utf8)
        guard i + needle.count <= scanEnd else { return false }
        for offset in needle.indices {
            if bytes[i + offset] != needle[offset] { return false }
        }
        let after = i + needle.count
        if after < scanEnd {
            let next = bytes[after]
            if isBareKeyChar(next) { return false }
        }
        return true
    }

    mutating func finishTables() {
        let lastEnd = i
        for index in headers.indices {
            guard foldables.count < budget.maxFoldables else {
                markTruncated()
                return
            }
            let header = headers[index]
            let nextStart: Int
            let closerLine: Int
            if index + 1 < headers.count {
                nextStart = headers[index + 1].openerLineStart
                closerLine = max(header.openerLine, headers[index + 1].openerLine - 1)
            } else {
                nextStart = lastEnd
                closerLine = max(header.openerLine, line)
            }
            let openerEnd = endOffset(ofLine: header.openerLine)
            let proposed = openerEnd..<nextStart
            guard !proposed.isEmpty, openerEnd < nextStart else { continue }
            let opening = openingLineText(start: header.openerLineStart, line: header.openerLine)
            let column = header.openerOffset - header.openerLineStart
            let anchor = FoldAnchor.digest("\(opening)\n\(column)")
            foldables.append(Block(
                id: FoldID(kind: header.kind, startLine: header.openerLine, anchor: anchor),
                kind: .other,
                bytes: header.openerOffset..<nextStart,
                lines: header.openerLine..<(closerLine + 1),
                foldExtent: proposed
            ))
        }
    }

    mutating func skipComment() {
        let start = i
        i += 1
        while let b = peek, b != 0x0A {
            i += 1
        }
        addHighlight(start..<i, role: .comment)
    }

    mutating func skipLineSpace() {
        while let b = peek, b == 0x20 || b == 0x09 || b == 0x0D {
            i += 1
        }
    }

    mutating func skipSpaceCommentsAndNewlines() {
        while !atEnd {
            skipLineSpace()
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            if peek == UInt8(ascii: "#") {
                skipComment()
                continue
            }
            return
        }
    }

    mutating func skipToNewline() {
        while let b = peek, b != 0x0A {
            i += 1
        }
    }

    mutating func recoverToArrayEnd() {
        while let b = peek {
            if b == UInt8(ascii: "]") { return }
            if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") {
                _ = parseString(allowMultiline: true)
                continue
            }
            if b == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
    }

    mutating func recoverToInlineTableEnd() {
        while let b = peek {
            if b == UInt8(ascii: "}") { return }
            if b == 0x0A { return }
            if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") {
                _ = parseString(allowMultiline: false)
                continue
            }
            i += 1
        }
    }

    mutating func consumeNewline() {
        guard peek == 0x0A else { return }
        i += 1
        line += 1
        lineStart = i
        lineStarts.append(i)
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

    func decode(_ range: Range<Int>) -> String {
        guard range.lowerBound < range.upperBound, range.upperBound <= bytes.count else { return "" }
        return String(decoding: bytes[range], as: UTF8.self)
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
        if headers.count >= budget.maxFoldables {
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
            message: "TOML scan stopped at size or time budget",
            severity: .warning
        )
    }
}

private func isBareKeyChar(_ b: UInt8) -> Bool {
    (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
        || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
        || b == UInt8(ascii: "_")
        || b == UInt8(ascii: "-")
}

private func isAtomicValueChar(_ b: UInt8) -> Bool {
    isBareKeyChar(b)
        || b == UInt8(ascii: "+")
        || b == UInt8(ascii: ":")
        || b == UInt8(ascii: ".")
        || b == UInt8(ascii: "T")
        || b == UInt8(ascii: "Z")
        || b == UInt8(ascii: "t")
        || b == UInt8(ascii: "z")
}

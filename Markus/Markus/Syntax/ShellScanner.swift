import Foundation

/// Bounds for a shell scan so a multi-MB buffer cannot freeze typing (N2).
/// Same caps as `BraceScanBudget`. Over budget: stop, keep partial work.
struct ShellScanBudget: Sendable {
    var maxBytes: Int
    var maxFoldables: Int
    var maxOutlineRows: Int
    var maxHighlightSpans: Int
    var timeLimitNanoseconds: UInt64?

    static let unbounded = ShellScanBudget(
        maxBytes: Int.max,
        maxFoldables: Int.max,
        maxOutlineRows: Int.max,
        maxHighlightSpans: Int.max,
        timeLimitNanoseconds: nil
    )

    static let `default` = ShellScanBudget(
        maxBytes: 2_097_152,
        maxFoldables: 4_096,
        maxOutlineRows: 2_048,
        maxHighlightSpans: 4_096,
        timeLimitNanoseconds: 50_000_000
    )
}

struct ShellScanResult: Equatable, Sendable {
    var foldables: [Block]
    var outlineRows: [OutlineItem]
    var diagnostics: [ParseDiagnostic]
    var highlightSpans: [HighlightSpan]
}

/// Best-effort shell coloring and `{…}` folds (`function name {`, `name() {`).
/// Skips quotes and `${…}` so expansion cannot steal a closer. `#` comments
/// and keywords are highlighted. Indent / `if`/`fi` folds are not attempted.
/// Typical `.sh` must not crash: unmatched `}` is ignored; budget stops the scan.
enum ShellScanner {
    static func scan(
        _ buffer: String,
        budget: ShellScanBudget = .unbounded
    ) -> ShellScanResult {
        var scanner = Engine(buffer: buffer, budget: budget)
        scanner.run()
        return scanner.result()
    }
}

private struct BraceOpen {
    var openerOffset: Int
    var openerLine: Int
    var openerLineStart: Int
    var level: Int
}

private struct Engine {
    let bytes: [UInt8]
    let budget: ShellScanBudget
    let scanEnd: Int
    let started: DispatchTime

    var i = 0
    var line = 1
    var lineStart = 0
    var lineStarts: [Int] = [0]
    var truncated = false

    var delimStack: [BraceOpen] = []
    var foldables: [Block] = []
    var outlineRows: [OutlineItem] = []
    var diagnostics: [ParseDiagnostic] = []
    var highlightSpans: [HighlightSpan] = []

    init(buffer: String, budget: ShellScanBudget) {
        bytes = Array(buffer.utf8)
        self.budget = budget
        scanEnd = min(bytes.count, budget.maxBytes)
        started = .now()
    }

    func result() -> ShellScanResult {
        ShellScanResult(
            foldables: foldables,
            outlineRows: outlineRows,
            diagnostics: diagnostics,
            highlightSpans: highlightSpans
        )
    }

    mutating func run() {
        skipBOM()
        scanCode()
        if truncated { return }
        for open in delimStack {
            addDiagnostic(line: open.openerLine, message: "Unclosed block", severity: .error)
        }
        if scanEnd < bytes.count {
            markTruncated()
        }
    }

    mutating func scanCode() {
        while !atEnd && !truncated {
            if isOverBudget() { return }
            guard let b = peek else { return }
            switch b {
            case UInt8(ascii: "#"):
                if i > 0, bytes[i - 1] == UInt8(ascii: "$") {
                    i += 1
                } else {
                    skipHashComment()
                }
            case UInt8(ascii: "'"), UInt8(ascii: "\""), UInt8(ascii: "`"):
                skipQuotedString(quote: b)
            case UInt8(ascii: "$"):
                if peek(at: 1) == UInt8(ascii: "{") {
                    skipParamExpansion()
                } else if peek(at: 1) == UInt8(ascii: "'") || peek(at: 1) == UInt8(ascii: "\"") {
                    i += 1
                    skipQuotedString(quote: peek ?? UInt8(ascii: "'"))
                } else {
                    i += 1
                }
            case UInt8(ascii: "{"):
                openBrace()
            case UInt8(ascii: "}"):
                closeBrace()
            case 0x0A:
                consumeNewline()
            default:
                if isDigit(b) {
                    skipNumber()
                } else if isIdentStart(b) {
                    skipIdentOrKeyword()
                } else {
                    i += 1
                }
            }
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

    mutating func openBrace() {
        let openerOffset = i
        let openerLine = line
        let openerLineStart = lineStart
        let level = delimStack.count
        i += 1
        guard foldables.count < budget.maxFoldables else {
            markTruncated()
            return
        }
        delimStack.append(BraceOpen(
            openerOffset: openerOffset,
            openerLine: openerLine,
            openerLineStart: openerLineStart,
            level: level
        ))
        addOutlineRow(
            title: outlineTitle(start: openerLineStart, line: openerLine),
            sourceLine: openerLine,
            level: level
        )
    }

    /// Unmatched `}` is ignored so a typical `.sh` cannot crash the scan.
    mutating func closeBrace() {
        i += 1
        guard let open = delimStack.popLast() else { return }
        let closerEnd = i
        let openerEnd = endOffset(ofLine: open.openerLine)
        let proposed = openerEnd..<closerEnd
        guard !proposed.isEmpty, openerEnd < closerEnd else { return }
        guard foldables.count < budget.maxFoldables else {
            markTruncated()
            return
        }
        let opening = openingLineText(start: open.openerLineStart, line: open.openerLine)
        let column = open.openerOffset - open.openerLineStart
        let anchor = FoldAnchor.digest("\(opening)\n\(column)")
        let closerLine = max(open.openerLine, line)
        foldables.append(Block(
            id: FoldID(kind: .brace, startLine: open.openerLine, anchor: anchor),
            kind: .other,
            bytes: open.openerOffset..<closerEnd,
            lines: open.openerLine..<(closerLine + 1),
            foldExtent: proposed
        ))
    }

    mutating func skipHashComment() {
        let start = i
        i += 1
        while let b = peek, b != 0x0A {
            i += 1
        }
        addHighlight(start..<i, role: .comment)
    }

    /// `${…}` including nested braces. Not a fold unit.
    mutating func skipParamExpansion() {
        i += 2
        var depth = 1
        while !atEnd, depth > 0 {
            guard let b = peek else { return }
            switch b {
            case UInt8(ascii: "'"), UInt8(ascii: "\""), UInt8(ascii: "`"):
                skipQuotedString(quote: b)
            case UInt8(ascii: "{"):
                depth += 1
                i += 1
            case UInt8(ascii: "}"):
                depth -= 1
                i += 1
            case 0x0A:
                consumeNewline()
            default:
                i += 1
            }
        }
    }

    mutating func skipQuotedString(quote: UInt8) {
        let start = i
        let startLine = line
        i += 1
        while let b = peek {
            if b == quote {
                i += 1
                addHighlight(start..<i, role: .string)
                return
            }
            if quote != UInt8(ascii: "'"), b == UInt8(ascii: "\\") {
                i += 1
                if peek == 0x0A {
                    consumeNewline()
                } else if peek != nil {
                    i += 1
                }
                continue
            }
            if b == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
    }

    mutating func skipIdentOrKeyword() {
        let start = i
        while let b = peek, isIdentContinue(b) {
            i += 1
        }
        let word = decode(start..<i)
        if shellKeywords.contains(word) {
            addHighlight(start..<i, role: .keyword)
        }
    }

    mutating func skipNumber() {
        let start = i
        while let b = peek, isDigit(b) {
            i += 1
        }
        addHighlight(start..<i, role: .number)
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

    func outlineTitle(start: Int, line: Int) -> String {
        let text = openingLineText(start: start, line: line)
            .trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("{") {
            let trimmed = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "{" : trimmed
        }
        return text.isEmpty ? "{" : text
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
            message: "Shell scan stopped at size or time budget",
            severity: .warning
        )
    }
}

private func isDigit(_ b: UInt8) -> Bool {
    b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")
}

private func isIdentStart(_ b: UInt8) -> Bool {
    (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
        || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || b == UInt8(ascii: "_")
        || b >= 0x80
}

private func isIdentContinue(_ b: UInt8) -> Bool {
    isIdentStart(b) || isDigit(b)
}

private let shellKeywords: Set<String> = [
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
    "case", "esac", "in", "function", "select", "time", "coproc",
    "true", "false", "return", "break", "continue", "exit",
    "export", "local", "readonly", "declare", "typeset", "unset",
    "shift", "eval", "exec", "source", "trap", "wait",
    "set", "alias", "unalias", "let", "test",
]

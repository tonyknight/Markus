import Foundation

/// Bounds for a brace-language scan so a multi-MB buffer cannot freeze
/// typing (N2). Profiles use `default`; callers that need a full pass
/// pass `unbounded`.
struct BraceScanBudget: Sendable {
    var maxBytes: Int
    var maxFoldables: Int
    var maxOutlineRows: Int
    var maxHighlightSpans: Int
    var timeLimitNanoseconds: UInt64?

    static let unbounded = BraceScanBudget(
        maxBytes: Int.max,
        maxFoldables: Int.max,
        maxOutlineRows: Int.max,
        maxHighlightSpans: Int.max,
        timeLimitNanoseconds: nil
    )

    /// Prefix + foldable/span caps + 50 ms, same spirit as `JSONScanBudget`.
    static let `default` = BraceScanBudget(
        maxBytes: 2_097_152,
        maxFoldables: 4_096,
        maxOutlineRows: 2_048,
        maxHighlightSpans: 4_096,
        timeLimitNanoseconds: 50_000_000
    )
}

/// Comment / string / interpolation rules for the shared brace matcher.
enum BraceDialect: Equatable, Sendable {
    /// `{` after a selector or at-rule. Skip `/* */` and strings. `url()` is not a fold.
    case css
    /// JS and TS (including `.tsx`). Skip `//`, `/* */`, strings, template `${}`.
    case javascript
    /// Skip `//`, nested `/* */`, strings. Fold `{` for type/func/closure.
    case swift
}

struct BraceScanResult: Equatable, Sendable {
    var foldables: [Block]
    var outlineRows: [OutlineItem]
    var diagnostics: [ParseDiagnostic]
    var highlightSpans: [HighlightSpan]
}

/// Shared brace/block scanner for CSS, JavaScript/TypeScript, and Swift.
/// Folds `{…}` that span past the opener line (opener stays visible).
/// `Block.kind` is `.other` so Markdown Preview substitution never treats
/// these as fences. `FoldID.Kind` is `.brace`. JSX tags are not fold units.
enum BraceScanner {
    static func scan(
        _ buffer: String,
        dialect: BraceDialect,
        budget: BraceScanBudget = .unbounded
    ) -> BraceScanResult {
        var scanner = Engine(buffer: buffer, dialect: dialect, budget: budget)
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

/// `{` folds vs `${` interpolation. A `}` pops the top frame so
/// interpolation cannot steal an outer function/class brace.
private enum Delim {
    case brace(BraceOpen)
    case jsInterpolation
}

/// Frames that resume a Swift string after `\(` interpolation.
private enum InterpFrame {
    case swiftString(quote: UInt8, stringStart: Int, isMultiline: Bool, hashCount: Int, parenDepth: Int)
}

private struct Engine {
    let bytes: [UInt8]
    let dialect: BraceDialect
    let budget: BraceScanBudget
    let scanEnd: Int
    let started: DispatchTime

    var i = 0
    var line = 1
    var lineStart = 0
    var lineStarts: [Int] = [0]
    var truncated = false

    var delimStack: [Delim] = []
    var interpStack: [InterpFrame] = []
    var foldables: [Block] = []
    var outlineRows: [OutlineItem] = []
    var diagnostics: [ParseDiagnostic] = []
    var highlightSpans: [HighlightSpan] = []
    /// Last non-whitespace, non-comment code byte. Used to tell `/regex/` from division.
    var lastSignificant: UInt8?
    /// `return /foo/` must start a regex even though the previous token is an ident.
    var lastWasRegexPrefixKeyword = false

    init(buffer: String, dialect: BraceDialect, budget: BraceScanBudget) {
        bytes = Array(buffer.utf8)
        self.dialect = dialect
        self.budget = budget
        scanEnd = min(bytes.count, budget.maxBytes)
        started = .now()
    }

    func result() -> BraceScanResult {
        BraceScanResult(
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
        for frame in delimStack {
            if case .brace(let open) = frame {
                addDiagnostic(line: open.openerLine, message: "Unclosed block", severity: .error)
            }
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
            case UInt8(ascii: "/"):
                if peek(at: 1) == UInt8(ascii: "*") {
                    skipBlockComment()
                } else if dialect != .css, peek(at: 1) == UInt8(ascii: "/") {
                    skipLineComment()
                } else if dialect != .css, canStartRegex {
                    skipRegex()
                } else {
                    noteSignificant(b)
                    i += 1
                }
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                skipQuotedString(quote: b)
                noteSignificant(b)
            case UInt8(ascii: "`"):
                if dialect == .javascript {
                    skipTemplateLiteral()
                    noteSignificant(UInt8(ascii: "`"))
                } else {
                    noteSignificant(b)
                    i += 1
                }
            case UInt8(ascii: "#"):
                if dialect == .swift, peek(at: 1) == UInt8(ascii: "\"") {
                    skipSwiftRawString()
                    noteSignificant(UInt8(ascii: "\""))
                } else if dialect == .css {
                    skipHashOrNumber()
                    noteSignificant(b)
                } else {
                    noteSignificant(b)
                    i += 1
                }
            case UInt8(ascii: "{"):
                noteSignificant(b)
                openBrace()
            case UInt8(ascii: "}"):
                noteSignificant(b)
                closeBraceOrInterpolation()
            case UInt8(ascii: "("):
                noteSignificant(b)
                i += 1
                bumpSwiftInterpParen(delta: 1)
            case UInt8(ascii: ")"):
                noteSignificant(b)
                closeSwiftInterpParenOrAdvance()
            case 0x0A:
                consumeNewline()
            default:
                if isDigit(b) {
                    skipNumber()
                } else if isIdentStart(b) {
                    skipIdentOrKeyword()
                } else if b == UInt8(ascii: ".") && isDigit(peek(at: 1) ?? 0) {
                    skipNumber()
                } else if b == UInt8(ascii: "@"), dialect == .css {
                    skipCSSAtRule()
                } else {
                    if !isHorizontalSpace(b) {
                        noteSignificant(b)
                    }
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

    private var canStartRegex: Bool {
        if lastWasRegexPrefixKeyword { return true }
        guard let last = lastSignificant else { return true }
        if isIdentContinue(last) || isDigit(last) { return false }
        switch last {
        case UInt8(ascii: ")"), UInt8(ascii: "]"):
            return false
        default:
            return true
        }
    }

    mutating func noteSignificant(_ b: UInt8) {
        lastSignificant = b
        lastWasRegexPrefixKeyword = false
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
        let level = delimStack.reduce(0) { count, frame in
            if case .brace = frame { return count + 1 }
            return count
        }
        i += 1
        guard foldables.count < budget.maxFoldables else {
            markTruncated()
            return
        }
        delimStack.append(.brace(BraceOpen(
            openerOffset: openerOffset,
            openerLine: openerLine,
            openerLineStart: openerLineStart,
            level: level
        )))
        addOutlineRow(
            title: outlineTitle(start: openerLineStart, line: openerLine),
            sourceLine: openerLine,
            level: level
        )
    }

    mutating func closeBraceOrInterpolation() {
        i += 1
        guard let top = delimStack.popLast() else { return }
        switch top {
        case .brace(let open):
            finishBrace(open)
        case .jsInterpolation:
            resumeJSTemplate()
        }
    }

    mutating func finishBrace(_ open: BraceOpen) {
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

    // MARK: Comments

    mutating func skipLineComment() {
        let start = i
        i += 2
        while let b = peek, b != 0x0A {
            i += 1
        }
        addHighlight(start..<i, role: .comment)
    }

    mutating func skipBlockComment() {
        let start = i
        let startLine = line
        i += 2
        var depth = 1
        while !atEnd {
            if dialect == .swift, peek == UInt8(ascii: "/"), peek(at: 1) == UInt8(ascii: "*") {
                depth += 1
                i += 2
                continue
            }
            if peek == UInt8(ascii: "*"), peek(at: 1) == UInt8(ascii: "/") {
                i += 2
                depth -= 1
                if depth == 0 {
                    addHighlight(start..<i, role: .comment)
                    return
                }
                continue
            }
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed comment", severity: .error)
        addHighlight(start..<i, role: .comment)
    }

    /// `/…/` regex (JS/TS) or Swift regex literal. `{`/`}` inside must not
    /// count as block delimiters (R13).
    mutating func skipRegex() {
        let start = i
        let startLine = line
        i += 1
        var inClass = false
        while let b = peek {
            if b == 0x0A { break }
            if b == UInt8(ascii: "\\") {
                i += 1
                if peek == 0x0A {
                    consumeNewline()
                } else if peek != nil {
                    i += 1
                }
                continue
            }
            if inClass {
                if b == UInt8(ascii: "]") { inClass = false }
                i += 1
                continue
            }
            if b == UInt8(ascii: "[") {
                inClass = true
                i += 1
                continue
            }
            if b == UInt8(ascii: "/") {
                i += 1
                while let flag = peek, isRegexFlag(flag) {
                    i += 1
                }
                addHighlight(start..<i, role: .string)
                noteSignificant(UInt8(ascii: "/"))
                return
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed regular expression", severity: .error)
        addHighlight(start..<i, role: .string)
        noteSignificant(UInt8(ascii: "/"))
    }

    // MARK: Strings

    mutating func skipQuotedString(quote: UInt8) {
        if dialect == .swift, quote == UInt8(ascii: "\""), peek(at: 1) == quote, peek(at: 2) == quote {
            skipSwiftMultilineString()
            return
        }
        let start = i
        let startLine = line
        i += 1
        while let b = peek {
            if b == quote {
                i += 1
                addHighlight(start..<i, role: .string)
                return
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                if dialect == .swift, peek == UInt8(ascii: "(") {
                    addHighlight(start..<i, role: .string)
                    i += 1
                    interpStack.append(.swiftString(
                        quote: quote,
                        stringStart: i,
                        isMultiline: false,
                        hashCount: 0,
                        parenDepth: 1
                    ))
                    return
                }
                if peek == 0x0A {
                    consumeNewline()
                } else if peek != nil {
                    i += 1
                }
                continue
            }
            if b == 0x0A {
                if dialect == .javascript {
                    addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
                    addHighlight(start..<i, role: .string)
                    return
                }
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
    }

    mutating func skipSwiftMultilineString() {
        let start = i
        let startLine = line
        i += 3
        while !atEnd {
            if peek == UInt8(ascii: "\""), peek(at: 1) == UInt8(ascii: "\""), peek(at: 2) == UInt8(ascii: "\"") {
                i += 3
                addHighlight(start..<i, role: .string)
                return
            }
            if peek == UInt8(ascii: "\\"), peek(at: 1) == UInt8(ascii: "(") {
                addHighlight(start..<i, role: .string)
                i += 2
                interpStack.append(.swiftString(
                    quote: UInt8(ascii: "\""),
                    stringStart: i,
                    isMultiline: true,
                    hashCount: 0,
                    parenDepth: 1
                ))
                return
            }
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
    }

    mutating func skipSwiftRawString() {
        let start = i
        let startLine = line
        var hashes = 0
        while peek == UInt8(ascii: "#") {
            hashes += 1
            i += 1
        }
        guard peek == UInt8(ascii: "\"") else { return }
        i += 1
        while !atEnd {
            if peek == UInt8(ascii: "\"") {
                var matched = 0
                var look = 1
                while matched < hashes, peek(at: look) == UInt8(ascii: "#") {
                    matched += 1
                    look += 1
                }
                if matched == hashes {
                    i += 1 + hashes
                    addHighlight(start..<i, role: .string)
                    return
                }
            }
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
    }

    mutating func skipTemplateLiteral() {
        let start = i
        let startLine = line
        i += 1
        scanTemplateBody(stringStart: start, startLine: startLine)
    }

    mutating func scanTemplateBody(stringStart: Int, startLine: Int) {
        let start = stringStart
        while !atEnd {
            if peek == UInt8(ascii: "\\") {
                i += 1
                if peek == 0x0A {
                    consumeNewline()
                } else if peek != nil {
                    i += 1
                }
                continue
            }
            if peek == UInt8(ascii: "$"), peek(at: 1) == UInt8(ascii: "{") {
                addHighlight(start..<i, role: .string)
                i += 2
                delimStack.append(.jsInterpolation)
                return
            }
            if peek == UInt8(ascii: "`") {
                i += 1
                addHighlight(start..<i, role: .string)
                return
            }
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
    }

    mutating func resumeJSTemplate() {
        let startLine = line
        let stringStart = i
        scanTemplateBody(stringStart: stringStart, startLine: startLine)
    }

    mutating func bumpSwiftInterpParen(delta: Int) {
        guard !interpStack.isEmpty else { return }
        if case .swiftString(let quote, let stringStart, let isMultiline, let hashCount, let depth) = interpStack[interpStack.count - 1] {
            interpStack[interpStack.count - 1] = .swiftString(
                quote: quote,
                stringStart: stringStart,
                isMultiline: isMultiline,
                hashCount: hashCount,
                parenDepth: depth + delta
            )
        }
    }

    mutating func closeSwiftInterpParenOrAdvance() {
        guard !interpStack.isEmpty,
              case .swiftString(let quote, _, let isMultiline, let hashCount, let depth) = interpStack[interpStack.count - 1]
        else {
            i += 1
            return
        }
        if depth > 1 {
            bumpSwiftInterpParen(delta: -1)
            i += 1
            return
        }
        i += 1
        interpStack.removeLast()
        if isMultiline {
            continueSwiftMultilineAfterInterp(quote: quote, hashCount: hashCount)
        } else {
            continueSwiftStringAfterInterp(quote: quote)
        }
    }

    mutating func continueSwiftStringAfterInterp(quote: UInt8) {
        let start = i
        let startLine = line
        while let b = peek {
            if b == quote {
                i += 1
                addHighlight(start..<i, role: .string)
                return
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                if peek == UInt8(ascii: "(") {
                    addHighlight(start..<i, role: .string)
                    i += 1
                    interpStack.append(.swiftString(
                        quote: quote,
                        stringStart: i,
                        isMultiline: false,
                        hashCount: 0,
                        parenDepth: 1
                    ))
                    return
                }
                if peek != nil { i += 1 }
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

    mutating func continueSwiftMultilineAfterInterp(quote: UInt8, hashCount: Int) {
        _ = quote
        _ = hashCount
        let start = i
        let startLine = line
        while !atEnd {
            if peek == UInt8(ascii: "\""), peek(at: 1) == UInt8(ascii: "\""), peek(at: 2) == UInt8(ascii: "\"") {
                i += 3
                addHighlight(start..<i, role: .string)
                return
            }
            if peek == UInt8(ascii: "\\"), peek(at: 1) == UInt8(ascii: "(") {
                addHighlight(start..<i, role: .string)
                i += 2
                interpStack.append(.swiftString(
                    quote: UInt8(ascii: "\""),
                    stringStart: i,
                    isMultiline: true,
                    hashCount: 0,
                    parenDepth: 1
                ))
                return
            }
            if peek == 0x0A {
                consumeNewline()
                continue
            }
            i += 1
        }
        addDiagnostic(line: startLine, message: "Unclosed string", severity: .error)
        addHighlight(start..<i, role: .string)
    }

    // MARK: Idents, keywords, numbers

    mutating func skipIdentOrKeyword() {
        let start = i
        while let b = peek, isIdentContinue(b) {
            i += 1
        }
        let word = decode(start..<i)
        if keywords.contains(word) {
            addHighlight(start..<i, role: .keyword)
        }
        if start < i {
            noteSignificant(bytes[i - 1])
            lastWasRegexPrefixKeyword = javascriptRegexPrefixKeywords.contains(word)
        }
    }

    mutating func skipCSSAtRule() {
        let start = i
        i += 1
        while let b = peek, isIdentContinue(b) {
            i += 1
        }
        addHighlight(start..<i, role: .keyword)
    }

    mutating func skipNumber() {
        let start = i
        if peek == UInt8(ascii: ".") { i += 1 }
        while let b = peek {
            if isDigit(b) || b == UInt8(ascii: "_") || b == UInt8(ascii: ".") {
                i += 1
                continue
            }
            if b == UInt8(ascii: "e") || b == UInt8(ascii: "E") {
                i += 1
                if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { i += 1 }
                continue
            }
            if b == UInt8(ascii: "x") || b == UInt8(ascii: "X")
                || b == UInt8(ascii: "b") || b == UInt8(ascii: "B")
                || b == UInt8(ascii: "o") || b == UInt8(ascii: "O")
                || b == UInt8(ascii: "n") {
                i += 1
                continue
            }
            if dialect == .css, isIdentContinue(b) {
                // `10px`, `1.5rem`
                i += 1
                continue
            }
            break
        }
        addHighlight(start..<i, role: .number)
        if start < i {
            noteSignificant(bytes[i - 1])
        }
    }

    mutating func skipHashOrNumber() {
        let start = i
        i += 1
        while let b = peek, isHex(b) {
            i += 1
        }
        if i > start + 1 {
            addHighlight(start..<i, role: .number)
        }
    }

    var keywords: Set<String> {
        switch dialect {
        case .css:
            cssKeywords
        case .javascript:
            javascriptKeywords
        case .swift:
            swiftKeywords
        }
    }

    // MARK: Line / budget helpers

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
            message: "Brace scan stopped at size or time budget",
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

private func isIdentStart(_ b: UInt8) -> Bool {
    (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
        || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || b == UInt8(ascii: "_")
        || b == UInt8(ascii: "$")
        || b >= 0x80
}

private func isIdentContinue(_ b: UInt8) -> Bool {
    isIdentStart(b) || isDigit(b) || b == UInt8(ascii: "-")
}

private func isHorizontalSpace(_ b: UInt8) -> Bool {
    b == 0x09 || b == 0x0D || b == UInt8(ascii: " ")
}

private func isRegexFlag(_ b: UInt8) -> Bool {
    switch b {
    case UInt8(ascii: "g"), UInt8(ascii: "i"), UInt8(ascii: "m"),
         UInt8(ascii: "s"), UInt8(ascii: "u"), UInt8(ascii: "y"),
         UInt8(ascii: "d"), UInt8(ascii: "v"):
        true
    default:
        false
    }
}

private let cssKeywords: Set<String> = [
    "important", "and", "or", "not", "only", "from", "to", "through",
    "inherit", "initial", "unset", "none", "auto",
]

private let javascriptRegexPrefixKeywords: Set<String> = [
    "return", "typeof", "case", "throw", "new", "delete", "void",
    "in", "instanceof", "else", "await", "yield", "of", "as",
]

private let javascriptKeywords: Set<String> = [
    "await", "break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "enum", "export",
    "extends", "false", "finally", "for", "function", "if", "import",
    "in", "instanceof", "let", "new", "null", "return", "super",
    "switch", "this", "throw", "true", "try", "typeof", "var", "void",
    "while", "with", "yield", "async", "from", "of", "as", "type",
    "interface", "implements", "package", "private", "protected",
    "public", "static", "readonly", "abstract", "declare", "namespace",
    "module", "keyof", "infer", "satisfies", "override", "accessor",
]

private let swiftKeywords: Set<String> = [
    "associatedtype", "actor", "as", "break", "case", "catch", "class",
    "continue", "default", "defer", "deinit", "do", "else", "enum",
    "extension", "fallthrough", "false", "fileprivate", "func", "guard",
    "if", "import", "in", "init", "inout", "internal", "is", "let",
    "nil", "open", "operator", "precedencegroup", "private", "protocol",
    "public", "repeat", "rethrows", "return", "self", "Self", "static",
    "struct", "subscript", "super", "switch", "throw", "throws", "true",
    "try", "typealias", "var", "where", "while", "async", "await",
    "some", "any", "consuming", "borrowing", "isolated", "nonisolated",
    "each", "package", "macro",
]

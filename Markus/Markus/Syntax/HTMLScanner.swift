import Foundation

/// Bounds for an HTML/SVG scan so a multi-MB buffer cannot freeze typing (N2).
/// Profiles use `default`; callers that need a full pass pass `unbounded`.
struct HTMLScanBudget: Sendable {
    var maxBytes: Int
    var maxFoldables: Int
    var maxOutlineRows: Int
    var maxHighlightSpans: Int
    var timeLimitNanoseconds: UInt64?

    static let unbounded = HTMLScanBudget(
        maxBytes: Int.max,
        maxFoldables: Int.max,
        maxOutlineRows: Int.max,
        maxHighlightSpans: Int.max,
        timeLimitNanoseconds: nil
    )

    /// Prefix + foldable/span caps + 50 ms, same spirit as `JSONScanBudget`.
    static let `default` = HTMLScanBudget(
        maxBytes: 2_097_152,
        maxFoldables: 4_096,
        maxOutlineRows: 2_048,
        maxHighlightSpans: 4_096,
        timeLimitNanoseconds: 50_000_000
    )
}

/// HTML5 vs XML/SVG matching rules. Same tokenizer either way.
enum HTMLScanDialect: Equatable, Sendable {
    /// Case-insensitive names, HTML void elements, rawtext (`script`/`style`).
    case html
    /// Case-sensitive names, no HTML void list, CDATA sections (SVG).
    case xml
}

struct HTMLScanResult: Equatable, Sendable {
    var foldables: [Block]
    var outlineRows: [OutlineItem]
    var diagnostics: [ParseDiagnostic]
    var highlightSpans: [HighlightSpan]
}

/// Shared XML/HTML tokenizer for HTML and SVG. Emits element folds whose
/// matching end tag falls on a later line than the opener. Void and
/// self-closing tags are not foldable. `Block.kind` is `.other` so
/// Markdown Preview substitution (keyed off `.fence`) never treats these
/// as fences.
enum HTMLScanner {
    static func scan(
        _ buffer: String,
        dialect: HTMLScanDialect,
        budget: HTMLScanBudget = .unbounded
    ) -> HTMLScanResult {
        var scanner = Engine(buffer: buffer, dialect: dialect, budget: budget)
        scanner.run()
        return scanner.result()
    }
}

private struct OpenElement {
    var name: String
    var openerOffset: Int
    var openerLine: Int
    var openerLineStart: Int
}

private struct Engine {
    let bytes: [UInt8]
    let dialect: HTMLScanDialect
    let budget: HTMLScanBudget
    let scanEnd: Int
    let started: DispatchTime

    var i = 0
    var line = 1
    var lineStart = 0
    var lineStarts: [Int] = [0]
    var truncated = false

    var stack: [OpenElement] = []
    var foldables: [Block] = []
    var outlineRows: [OutlineItem] = []
    var diagnostics: [ParseDiagnostic] = []
    var highlightSpans: [HighlightSpan] = []

    init(buffer: String, dialect: HTMLScanDialect, budget: HTMLScanBudget) {
        bytes = Array(buffer.utf8)
        self.dialect = dialect
        self.budget = budget
        scanEnd = min(bytes.count, budget.maxBytes)
        started = .now()
    }

    func result() -> HTMLScanResult {
        HTMLScanResult(
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
            guard peek == UInt8(ascii: "<") else {
                advanceOne()
                continue
            }
            parseMarkup()
        }
        if truncated { return }
        if scanEnd < bytes.count {
            markTruncated()
            return
        }
        for leftover in stack.reversed() {
            addDiagnostic(
                line: leftover.openerLine,
                message: "Unclosed <\(leftover.name)>",
                severity: .error
            )
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

    mutating func parseMarkup() {
        let next = peek(at: 1)
        if next == UInt8(ascii: "!") {
            parseDeclarationOrComment()
            return
        }
        if next == UInt8(ascii: "?") {
            parseProcessingInstruction()
            return
        }
        if next == UInt8(ascii: "/") {
            parseEndTag()
            return
        }
        parseStartTag()
    }

    mutating func parseStartTag() {
        let openerOffset = i
        let openerLine = line
        let openerLineStart = lineStart
        i += 1
        skipTagWhitespace()
        guard let nameRange = readTagName() else {
            addDiagnostic(line: openerLine, message: "Malformed tag", severity: .error)
            return
        }
        let rawName = decode(nameRange)
        let name = normalized(rawName)
        addHighlight(nameRange, role: .keyword)

        var elementID: String?
        var firstClass: String?
        var selfClosing = false

        attributes: while !atEnd && !truncated {
            skipTagWhitespace()
            guard let b = peek else {
                addDiagnostic(line: openerLine, message: "Unclosed start tag", severity: .error)
                return
            }
            if b == UInt8(ascii: ">") {
                i += 1
                break attributes
            }
            if b == UInt8(ascii: "/") {
                i += 1
                skipTagWhitespace()
                if peek == UInt8(ascii: ">") {
                    i += 1
                    selfClosing = true
                    break attributes
                }
                continue
            }
            guard let attr = readAttribute() else {
                addDiagnostic(line: line, message: "Malformed attribute", severity: .error)
                recoverToTagEnd()
                return
            }
            if attr.name == "id", elementID == nil {
                elementID = attr.value
            } else if attr.name == "class", firstClass == nil {
                firstClass = attr.value.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            }
        }

        let isVoid = dialect == .html && htmlVoidElements.contains(name)
        if !selfClosing && !isVoid {
            addOutlineRow(
                title: outlineTitle(tag: rawName, id: elementID, firstClass: firstClass),
                sourceLine: openerLine,
                level: stack.count
            )
            stack.append(OpenElement(
                name: name,
                openerOffset: openerOffset,
                openerLine: openerLine,
                openerLineStart: openerLineStart
            ))
            if dialect == .html, htmlRawtextElements.contains(name) {
                consumeRawtext(untilEndTag: name)
            }
        }
    }

    mutating func parseEndTag() {
        let startLine = line
        i += 1
        i += 1
        skipTagWhitespace()
        guard let nameRange = readTagName() else {
            addDiagnostic(line: startLine, message: "Malformed end tag", severity: .error)
            recoverToTagEnd()
            return
        }
        let name = normalized(decode(nameRange))
        addHighlight(nameRange, role: .keyword)
        skipTagWhitespace()
        if peek == UInt8(ascii: "/") { i += 1 }
        skipTagWhitespace()
        if peek == UInt8(ascii: ">") {
            i += 1
        } else {
            addDiagnostic(line: line, message: "Malformed end tag", severity: .error)
            recoverToTagEnd()
        }
        closeElement(named: name, atLine: startLine)
    }

    mutating func closeElement(named name: String, atLine closerLine: Int) {
        guard let matchIndex = stack.lastIndex(where: { $0.name == name }) else {
            addDiagnostic(line: closerLine, message: "Unexpected </\(name)>", severity: .error)
            return
        }
        if matchIndex < stack.count - 1 {
            for skipped in stack[(matchIndex + 1)...].reversed() {
                addDiagnostic(
                    line: skipped.openerLine,
                    message: "Unclosed <\(skipped.name)>",
                    severity: .error
                )
            }
        }
        let opener = stack[matchIndex]
        stack.removeSubrange(matchIndex...)
        finishElement(opener)
    }

    mutating func finishElement(_ opener: OpenElement) {
        let closerEnd = i
        let openerEnd = endOffset(ofLine: opener.openerLine)
        guard let proposed = Block.extentAfterOpenerLine(openerEnd: openerEnd, closerEnd: closerEnd) else { return }
        guard opener.openerOffset <= closerEnd else { return }
        guard foldables.count < budget.maxFoldables else {
            markTruncated()
            return
        }
        let opening = openingLineText(start: opener.openerLineStart, line: opener.openerLine)
        let column = opener.openerOffset - opener.openerLineStart
        let anchor = FoldAnchor.digest("\(opening)\n\(column)")
        let closerLine = max(opener.openerLine, line)
        foldables.append(Block(
            id: FoldID(kind: .element, startLine: opener.openerLine, anchor: anchor),
            kind: .other,
            bytes: opener.openerOffset..<closerEnd,
            lines: opener.openerLine..<(closerLine + 1),
            foldExtent: proposed
        ))
    }

    mutating func parseDeclarationOrComment() {
        let start = i
        let startLine = line
        i += 2
        if hasPrefix("--") {
            i += 2
            while !atEnd {
                if hasPrefix("-->") {
                    i += 3
                    addHighlight(start..<i, role: .comment)
                    return
                }
                advanceOne()
            }
            addDiagnostic(line: startLine, message: "Unclosed comment", severity: .error)
            addHighlight(start..<i, role: .comment)
            return
        }
        if dialect == .xml, hasPrefix("[CDATA[") {
            i += 7
            while !atEnd {
                if hasPrefix("]]>") {
                    i += 3
                    return
                }
                advanceOne()
            }
            addDiagnostic(line: startLine, message: "Unclosed CDATA section", severity: .error)
            return
        }
        while let b = peek {
            if b == UInt8(ascii: ">") {
                i += 1
                return
            }
            advanceOne()
        }
        addDiagnostic(line: startLine, message: "Unclosed declaration", severity: .error)
    }

    mutating func parseProcessingInstruction() {
        let startLine = line
        i += 2
        while !atEnd {
            if hasPrefix("?>") {
                i += 2
                return
            }
            advanceOne()
        }
        addDiagnostic(line: startLine, message: "Unclosed processing instruction", severity: .error)
    }

    /// Skip markup inside `<script>` / `<style>` until the matching end tag
    /// (left unconsumed so `parseEndTag` can close the stack).
    mutating func consumeRawtext(untilEndTag name: String) {
        while !atEnd && !truncated {
            if peek == UInt8(ascii: "<"), peek(at: 1) == UInt8(ascii: "/") {
                let save = i
                let saveLine = line
                let saveLineStart = lineStart
                let saveStarts = lineStarts.count
                i += 2
                skipTagWhitespace()
                if let range = readTagName(), normalized(decode(range)) == name {
                    restoreCursor(i: save, line: saveLine, lineStart: saveLineStart, lineStartsCount: saveStarts)
                    return
                }
                restoreCursor(i: save, line: saveLine, lineStart: saveLineStart, lineStartsCount: saveStarts)
            }
            advanceOne()
        }
    }

    mutating func readTagName() -> Range<Int>? {
        guard let first = peek, isNameStart(first) else { return nil }
        let start = i
        i += 1
        while let b = peek, isNameContinue(b) {
            i += 1
        }
        return start..<i
    }

    mutating func readAttribute() -> (name: String, value: String)? {
        guard let nameRange = readTagName() else { return nil }
        let attrName = normalized(decode(nameRange))
        skipTagWhitespace()
        guard peek == UInt8(ascii: "=") else {
            return (attrName, "")
        }
        i += 1
        skipTagWhitespace()
        let value: String
        if peek == UInt8(ascii: "\"") || peek == UInt8(ascii: "'") {
            let quote = peek!
            let valueStart = i
            i += 1
            while let b = peek, b != quote {
                advanceOne()
            }
            if peek == quote {
                addHighlight((valueStart)..<(i + 1), role: .string)
                value = decode((valueStart + 1)..<i)
                i += 1
            } else {
                addDiagnostic(line: line, message: "Unclosed attribute value", severity: .error)
                value = decode((valueStart + 1)..<i)
            }
        } else {
            let start = i
            while let b = peek, !isTagWhitespace(b), b != UInt8(ascii: ">"), b != UInt8(ascii: "/") {
                i += 1
            }
            value = decode(start..<i)
        }
        return (attrName, value)
    }

    mutating func recoverToTagEnd() {
        while let b = peek {
            if b == UInt8(ascii: ">") {
                i += 1
                return
            }
            advanceOne()
        }
    }

    mutating func skipTagWhitespace() {
        while let b = peek, isTagWhitespace(b) {
            advanceOne()
        }
    }

    func hasPrefix(_ text: String) -> Bool {
        let needle = Array(text.utf8)
        guard i + needle.count <= scanEnd else { return false }
        for offset in needle.indices {
            if bytes[i + offset] != needle[offset] { return false }
        }
        return true
    }

    mutating func restoreCursor(i: Int, line: Int, lineStart: Int, lineStartsCount: Int) {
        self.i = i
        self.line = line
        self.lineStart = lineStart
        if lineStarts.count > lineStartsCount {
            lineStarts.removeLast(lineStarts.count - lineStartsCount)
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

    func decode(_ range: Range<Int>) -> String {
        guard range.lowerBound < range.upperBound, range.upperBound <= bytes.count else { return "" }
        return String(decoding: bytes[range], as: UTF8.self)
    }

    func normalized(_ name: String) -> String {
        dialect == .html ? name.lowercased() : name
    }

    func outlineTitle(tag: String, id: String?, firstClass: String?) -> String {
        var title = dialect == .html ? tag.lowercased() : tag
        if let id, !id.isEmpty {
            title += "#\(id)"
        }
        if let firstClass, !firstClass.isEmpty {
            title += ".\(firstClass)"
        }
        return title
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
            message: "HTML scan stopped at size or time budget",
            severity: .warning
        )
    }
}

private let htmlVoidElements: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
]

private let htmlRawtextElements: Set<String> = [
    "script", "style", "textarea", "title",
]

private func isNameStart(_ b: UInt8) -> Bool {
    (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
        || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || b == UInt8(ascii: ":")
        || b == UInt8(ascii: "_")
}

private func isNameContinue(_ b: UInt8) -> Bool {
    isNameStart(b)
        || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
        || b == UInt8(ascii: "-")
        || b == UInt8(ascii: ".")
}

private func isTagWhitespace(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
}

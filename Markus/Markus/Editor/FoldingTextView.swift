import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#else
import UIKit
import SwiftUI
#endif

enum UTF8NSRange {
    /// A single conversion: `string.utf8.index(startIndex, offsetBy:)`
    /// walks from the very start of `string` every time it's called —
    /// fine for one-off use, pathological if called once per item in a
    /// loop over many items across a large document (see `nsRanges`
    /// below, added on this ticket after exactly that pattern was found
    /// to make `MarkdownPreviewRenderer.apply` effectively quadratic in
    /// document size, P4).
    static func nsRange(utf8Bytes: Range<Int>, in string: String) -> NSRange {
        let utf8 = string.utf8
        guard utf8Bytes.lowerBound >= 0,
              utf8Bytes.upperBound <= utf8.count,
              utf8Bytes.lowerBound <= utf8Bytes.upperBound
        else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let lower = utf8.index(utf8.startIndex, offsetBy: utf8Bytes.lowerBound)
        let upper = utf8.index(utf8.startIndex, offsetBy: utf8Bytes.upperBound)
        guard let stringLower = String.Index(lower, within: string),
              let stringUpper = String.Index(upper, within: string)
        else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(stringLower..<stringUpper, in: string)
    }

    /// Converts many UTF-8 byte ranges to `NSRange`s (UTF-16 offsets)
    /// in a single forward pass over `string` — O(document length +
    /// ranges·log(ranges)) total, instead of O(document length) spent
    /// *per range* by repeated calls to `nsRange(utf8Bytes:in:)` above.
    /// Byte-length and UTF-16-length per Unicode scalar are read
    /// directly off the scalar (`Unicode.Scalar.utf8.count`/
    /// `.utf16.count`), so this never touches `String.Index` distance
    /// computation — the thing that made the naive per-call approach
    /// slow, especially for the NSString-bridged string
    /// `NSTextStorage.string` returns (measured: applying ~3,954
    /// per-span attribute ranges to a 1 MB document this way took
    /// several tens of seconds via the naive path; this fixes it).
    /// `byteRanges` need not be sorted; the result preserves input
    /// order. A range whose bounds don't land on the needed-offset set
    /// (out of bounds, or lowerBound > upperBound) maps to
    /// `NSNotFound`.
    static func nsRanges(utf8Bytes byteRanges: [Range<Int>], in string: String) -> [NSRange] {
        guard !byteRanges.isEmpty else { return [] }

        var neededOffsets = Set<Int>()
        for range in byteRanges {
            neededOffsets.insert(range.lowerBound)
            neededOffsets.insert(range.upperBound)
        }
        let sortedOffsets = neededOffsets.sorted()

        var byteToUTF16: [Int: Int] = [:]
        byteToUTF16.reserveCapacity(sortedOffsets.count)
        var byteCursor = 0
        var utf16Cursor = 0
        var offsetIndex = 0

        func drain() {
            while offsetIndex < sortedOffsets.count, sortedOffsets[offsetIndex] <= byteCursor {
                byteToUTF16[sortedOffsets[offsetIndex]] = utf16Cursor
                offsetIndex += 1
            }
        }
        drain()

        for scalar in string.unicodeScalars {
            guard offsetIndex < sortedOffsets.count else { break }
            byteCursor += scalar.utf8.count
            utf16Cursor += scalar.utf16.count
            drain()
        }

        return byteRanges.map { range in
            guard let lower = byteToUTF16[range.lowerBound],
                  let upper = byteToUTF16[range.upperBound],
                  lower <= upper
            else {
                return NSRange(location: NSNotFound, length: 0)
            }
            return NSRange(location: lower, length: upper - lower)
        }
    }
}

final class FoldingTextLayoutFragment: NSTextLayoutFragment {
    /// A short placeholder shown in place of a folded fence's hidden body
    /// (R15) — the real text is never removed from the fragment's
    /// underlying element (N3); only what this fragment draws changes.
    static let placeholderText = "\u{22EF}"

    var isCollapsed = false
    var isPlaceholder = false

    override var layoutFragmentFrame: CGRect {
        var frame = super.layoutFragmentFrame
        if isCollapsed {
            frame.size.height = 0
        }
        return frame
    }

    override var renderingSurfaceBounds: CGRect {
        if isCollapsed {
            return .zero
        }
        return super.renderingSurfaceBounds
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        guard !isCollapsed else { return }
        if isPlaceholder {
            Self.drawPlaceholder(at: point, in: context)
            return
        }
        super.draw(at: point, in: context)
    }

    private static func drawPlaceholder(at point: CGPoint, in context: CGContext) {
        let text = placeholderText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.monospaced(size: 13),
            .foregroundColor: PlatformColor.secondaryLabel,
        ]
        #if os(macOS)
        context.saveGState()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(at: point, withAttributes: attributes)
        NSGraphicsContext.current = previous
        context.restoreGState()
        #else
        UIGraphicsPushContext(context)
        text.draw(at: point, withAttributes: attributes)
        UIGraphicsPopContext()
        #endif
    }
}

@MainActor
final class FoldingSession: NSObject, NSTextLayoutManagerDelegate {
    let foldStore: FoldStore
    private(set) var blocks: [Block] = []
    private(set) var mode: EditorMode
    private(set) var tokens: ThemeTokens
    private(set) var zoomScale: CGFloat = 1
    private(set) var collapsedFragmentCount = 0
    /// Fragments visited by the most recent `drawFragments` call — the
    /// N8 counter proving P1: bounded by the visible rect, not the
    /// document, so it must not scale with document size.
    private(set) var fragmentsEnumeratedLastDraw = 0
    /// Source lines examined by the most recent `packedSourceLineEntries`
    /// call — the N8 counter proving P2 when called with a bound.
    private(set) var sourceLinesScannedLastGutterCompute = 0
    /// Rebuilt only when the source text actually changes
    /// (`loadMarkdown`/`syncBlocksFromStorage`), not on every gutter
    /// compute — avoids re-scanning the whole document for line starts
    /// on every draw.
    private var cachedSourceMap: SourceMap?
    private var cachedUTF16LineOffsets: UTF16LineOffsets?
    /// The parsed (cmark-free) preview structure and raw-buffer spans,
    /// rebuilt only where the source text actually changes — never on
    /// a fold toggle, theme change, zoom step, mode switch, or resize
    /// (P3). `parsesPerformed` is the N8 counter proving it: it only
    /// increments inside `reparse(markdown:)`.
    private var parsedPreviewBlocks: [ParsedPreviewBlock] = []
    private var parsedSpans: [MarkdownSpan] = []
    private(set) var parsesPerformed = 0
    /// One source line per rendered Preview block's true start (R13),
    /// rebuilt only in `reparse` — never scanned per frame/viewport (P2).
    /// Built from every `parsedPreviewBlock` anchor **except**
    /// `.fenceDelimiter` (a fenced code block emits two of those — one
    /// per delimiter — purely so ticket 08's substitution machinery can
    /// hide each independently; a reader sees one fence, not two, so
    /// only the fence's own foldable-block start line below stands in
    /// for the whole thing), unioned with every foldable block's own
    /// start line (headings and fences, from `blocks`) so a fence is
    /// still numbered exactly once, at its real opening line.
    private(set) var previewBlockAnchorLines: Set<Int> = []
    /// The same set as `previewBlockAnchorLines`, pre-sorted ascending
    /// once here rather than via a `.sorted()` call inside the gutter's
    /// real per-frame draw path — used by `resolveOntoVisibleMap` (T01
    /// review fix), which requires its candidate list already ascending
    /// to binary-search and forward-scan it.
    private(set) var previewBlockAnchorLinesSorted: [Int] = []
    /// Total forward-scan steps performed by `resolveOntoVisibleMap`
    /// since the last `resetGutterResolutionSteps()` — the N8 counter
    /// proving the fix a review found necessary on this ticket: Preview's
    /// gutter draw originally called `nearestVisibleLine` once per
    /// document-wide candidate (every foldable block, every rendered
    /// block anchor), each call itself an O(viewport) scan — O((blocks +
    /// anchors) × viewport) per draw, the same O(document × viewport)
    /// shape ticket 10 fixed for `packedSourceLineEntries` (P2). Must
    /// stay bounded by the viewport's own entry count plus a small
    /// constant look-behind, never scale with total document anchor/
    /// block count.
    private(set) var gutterResolutionStepsLastDraw = 0
    /// Rebuilt only inside `applyStyling` (once per real state change:
    /// text/fold/mode/theme/zoom), not per fragment. `hiddenUTF16Ranges`
    /// and `placeholderUTF16Locations` used to be plain computed
    /// properties recomputed from scratch — including an O(document)
    /// byte→UTF-16 conversion per hidden block — every time
    /// `collapseState(for:layoutManager:)` read them; TextKit 2 calls
    /// that once per text element during every `ensureLayout()`/draw
    /// pass, so a document with many fragments recomputed the whole
    /// thing once per fragment (found on this ticket, T05, via direct
    /// process sampling of a hanging 5 MB test — a second, distinct
    /// quadratic bug from the `MarkdownPreviewRenderer` one).
    /// Sorted ascending by `location` (by `rebuildHiddenRangesCache`) so
    /// `collapseState` can binary-search it — O(log n) per fragment —
    /// instead of linearly scanning every hidden range per fragment,
    /// which stayed O(fragments × hidden_ranges) even after the cache
    /// itself stopped being *recomputed* per fragment (a third, distinct
    /// quadratic-shaped cost found on this ticket via direct process
    /// sampling of a hanging 5 MB test: a document with many folded/
    /// continuation ranges — e.g. one fence delimiter pair per fenced
    /// block — and many fragments still multiplied the two together).
    private var cachedHiddenUTF16Ranges: [NSRange] = []
    private var cachedPlaceholderUTF16Locations: Set<Int> = []
    /// N8 counter proving the fix: must stay flat across many fragment
    /// queries within one `ensureLayout()` call on a large document,
    /// incrementing only when `applyStyling` actually runs.
    private(set) var hiddenRangesCacheRebuildCount = 0
    /// N8 counter: total binary-search comparisons performed by
    /// `collapseState`'s hidden-range lookup. Must scale with
    /// fragments·log(hidden_ranges), never fragments·hidden_ranges —
    /// proves the binary search actually replaced the linear scan.
    private(set) var hiddenRangeLookupComparisons = 0
    private weak var layoutManager: NSTextLayoutManager?
    private weak var contentStorage: NSTextContentStorage?
    private weak var textStorage: NSTextStorage?
    let contentStorageDelegate = PreviewContentStorageDelegate()

    init(foldStore: FoldStore = FoldStore(), mode: EditorMode = .preview, tokens: ThemeTokens = .default) {
        self.foldStore = foldStore
        self.mode = mode
        self.tokens = tokens
    }

    func attach(layoutManager: NSTextLayoutManager, contentStorage: NSTextContentStorage) {
        self.layoutManager = layoutManager
        self.contentStorage = contentStorage
        layoutManager.delegate = self
        contentStorage.delegate = contentStorageDelegate
    }

    func loadMarkdown(_ markdown: String, into textStorage: NSTextStorage) {
        self.textStorage = textStorage
        reparse(markdown: markdown)
        textStorage.setAttributedString(NSAttributedString(string: markdown))
        applyStyling(to: textStorage)
        invalidateLayout()
    }

    /// The single place text-derived state is rebuilt: the fold block
    /// index, the line-start caches (T02/P2), and the cmark-free
    /// preview structure/raw-buffer spans `applyStyling` renders from.
    /// Called only where the source text actually changes
    /// (`loadMarkdown`, `syncBlocksFromStorage`) — never from
    /// `setMode`/`setTheme`/`setZoomScale`/`applyFolds`/resize, which
    /// only need to re-render the cached structure (P3).
    /// `parsesPerformed` is the N8 counter proving that boundary holds.
    private func reparse(markdown: String) {
        blocks = BlockIndex.build(markdown: markdown)
        cachedSourceMap = SourceMap(markdown: markdown)
        cachedUTF16LineOffsets = UTF16LineOffsets(markdown: markdown)
        parsedPreviewBlocks = PreviewStructureCollector.collect(markdown: markdown)
        parsedSpans = MarkdownParser().previewSpans(markdown)
        let nonFenceAnchors = parsedPreviewBlocks.compactMap { block -> Int? in
            if case .fenceDelimiter = block.kind { return nil }
            return block.lines.lowerBound
        }
        let foldableStartLines = blocks.compactMap { $0.foldExtent != nil ? $0.id.startLine : nil }
        previewBlockAnchorLines = Set(nonFenceAnchors).union(foldableStartLines)
        previewBlockAnchorLinesSorted = previewBlockAnchorLines.sorted()
        parsesPerformed += 1
    }

    /// Resolves `line` to the nearest source line at or after it that
    /// actually has a `SourceLineMap.Entry` in `map` — i.e. is genuinely
    /// rendered somewhere on screen. A block's own start line is
    /// sometimes itself invisible (a fence's opening delimiter is always
    /// markup-only and collapses to zero height, R10; an empty heading
    /// does too, per ticket 08's zero-length-substitution guard), so the
    /// gutter's chevron/number and jump-to-line's scroll target need the
    /// first line that is actually drawn, not necessarily the block's
    /// own first physical line. `map.entries` is ascending by
    /// `sourceLine` by construction (`packedSourceLineEntries` appends
    /// in increasing line order), so this returns as soon as it finds a
    /// candidate rather than scanning the whole array.
    func nearestVisibleLine(atOrAfter line: Int, in map: SourceLineMap) -> Int? {
        if map.y(forSourceLine: line) != nil { return line }
        for entry in map.entries where entry.sourceLine >= line {
            return entry.sourceLine
        }
        return nil
    }

    func resetGutterResolutionSteps() {
        gutterResolutionStepsLastDraw = 0
    }

    /// A short, constant bound on how many candidates before the
    /// viewport's own first line `resolveOntoVisibleMap` still considers
    /// — big enough to catch a short run of consecutive hidden anchors
    /// immediately preceding the viewport (e.g. two adjacent empty
    /// headings), never a document-proportional scan. Genuine gaps this
    /// codebase produces between a hidden anchor and its resolved
    /// position are always tiny (a fence delimiter resolves one line
    /// forward to its own body; an empty heading resolves one line
    /// forward to whatever follows), so this constant is generous
    /// headroom, not a load-bearing precise bound.
    private static let resolutionLookbehind = 64

    /// Batch form of `nearestVisibleLine`: resolves every one of
    /// `sortedCandidates` (ascending by `line`) against `map.entries`
    /// (ascending, already viewport-bounded) in a single binary-search-
    /// seeded forward pass — O(log candidates + resolutionLookbehind +
    /// candidates actually near the viewport + viewport entries), never
    /// O(candidates × viewport) the way calling `nearestVisibleLine` once
    /// per candidate costs. This is the fix for the review's Important
    /// finding on this ticket: `drawPreviewGutterNumbersAndChevrons`
    /// originally looped every document-wide foldable block and every
    /// document-wide preview-block anchor, calling `nearestVisibleLine`
    /// (itself O(viewport)) once per item — O((blocks + anchors) ×
    /// viewport) per draw, the same O(document × viewport) shape ticket
    /// 10 fixed for `packedSourceLineEntries` (P2). Binary search finds
    /// the first candidate at or after the viewport's first visible
    /// line, then backs up by `resolutionLookbehind` to also catch any
    /// candidate whose own line is hidden markup immediately preceding
    /// the viewport (see that constant's own doc comment). Returns each
    /// candidate paired with its payload and resolved `Entry` — multiple
    /// candidates legitimately sharing one resolved entry (several
    /// hidden anchors collapsing onto the same next-visible line) is
    /// preserved, exactly matching what per-candidate `nearestVisibleLine`
    /// calls would have produced. `gutterResolutionStepsLastDraw` counts
    /// every forward-loop step (N8).
    func resolveOntoVisibleMap<Payload>(
        _ sortedCandidates: [(line: Int, payload: Payload)],
        in map: SourceLineMap
    ) -> [(line: Int, payload: Payload, entry: SourceLineMap.Entry)] {
        guard let firstEntryLine = map.entries.first?.sourceLine else { return [] }
        let lastEntryLine = map.entries[map.entries.count - 1].sourceLine

        var low = 0
        var high = sortedCandidates.count
        while low < high {
            let mid = (low + high) / 2
            if sortedCandidates[mid].line < firstEntryLine {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let startIndex = max(0, low - Self.resolutionLookbehind)

        var result: [(Int, Payload, SourceLineMap.Entry)] = []
        var entryIndex = 0
        for index in startIndex..<sortedCandidates.count {
            gutterResolutionStepsLastDraw += 1
            let candidate = sortedCandidates[index]
            if candidate.line > lastEntryLine { break }
            while entryIndex < map.entries.count, map.entries[entryIndex].sourceLine < candidate.line {
                entryIndex += 1
            }
            guard entryIndex < map.entries.count else { break }
            result.append((candidate.line, candidate.payload, map.entries[entryIndex]))
        }
        return result
    }

    /// Convenience for candidates with no payload beyond their own line
    /// (the Preview number pass, whose candidates are just anchor lines).
    func resolveOntoVisibleMap(_ sortedLines: [Int], in map: SourceLineMap) -> [(line: Int, entry: SourceLineMap.Entry)] {
        resolveOntoVisibleMap(sortedLines.map { (line: $0, payload: ()) }, in: map)
            .map { (line: $0.line, entry: $0.entry) }
    }

    func setMode(_ mode: EditorMode, textStorage: NSTextStorage) {
        self.mode = mode
        self.textStorage = textStorage
        applyStyling(to: textStorage)
        invalidateLayout()
    }

    func setTheme(_ tokens: ThemeTokens, textStorage: NSTextStorage) {
        self.tokens = tokens
        self.textStorage = textStorage
        applyStyling(to: textStorage)
        invalidateLayout()
    }

    func setZoomScale(_ scale: CGFloat, textStorage: NSTextStorage) {
        zoomScale = max(0.5, min(scale, 3))
        self.textStorage = textStorage
        applyStyling(to: textStorage)
        invalidateLayout()
    }

    func applyFolds() {
        collapsedFragmentCount = 0
        if let textStorage {
            applyStyling(to: textStorage)
        }
        invalidateLayout()
    }

    func foldAll(textStorage: NSTextStorage) {
        self.textStorage = textStorage
        let foldableIDs = blocks.compactMap { $0.foldExtent != nil ? $0.id : nil }
        foldStore.foldAll(foldableIDs)
        applyFolds()
    }

    func unfoldAll(textStorage: NSTextStorage) {
        self.textStorage = textStorage
        foldStore.unfoldAll()
        applyFolds()
    }

    func ensureLayout() {
        guard let layoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        recountCollapsedFragments()
    }

    func syncBlocksFromStorage() {
        guard let textStorage else { return }
        reparse(markdown: textStorage.string)
        foldStore.repair(against: blocks)
        applyStyling(to: textStorage)
        invalidateLayout()
    }

    /// Binds the fold store to `url` (restoring whatever was persisted for
    /// it) and repairs the restored set against the block index already
    /// built from the just-loaded document (R16, R17's "open file" flow).
    func restoreFolds(for url: URL?) {
        foldStore.bind(to: url)
        foldStore.repair(against: blocks)
        applyFolds()
    }

    var layoutHeight: CGFloat {
        packedLayoutHeight()
    }

    /// `visibleRect`, when non-nil, bounds the underlying line scan to
    /// only the source lines the currently-visible packed fragments
    /// span (P2) — used by the gutter's per-frame paint path. Every
    /// other caller (jump-to-line, minimap, which must be able to
    /// resolve an off-screen line or Y) keeps calling this with no
    /// argument, preserving the full-document computation unchanged.
    func sourceLineMap(boundedBy visibleRect: CGRect? = nil) -> SourceLineMap {
        SourceLineMap(entries: packedSourceLineEntries(boundedBy: visibleRect))
    }

    /// Resolves `line`'s visual y directly when it has its own
    /// `SourceLineMap.Entry`. Otherwise (Preview only), `line` may be a
    /// non-anchor continuation of a multi-line substituted block (e.g.
    /// the 2nd/3rd physical line of a wrapped paragraph, or a table's
    /// data rows) — those never get their own entry by design (the whole
    /// block renders on its anchor line, T02). Resolving to the block's
    /// anchor, then to the nearest genuinely visible line at or after it
    /// (`nearestVisibleLine`, T01 — the anchor itself can also be
    /// invisible markup, e.g. a fence delimiter), gives go-to-line a real
    /// scroll target instead of silently doing nothing (T03).
    func y(forSourceLine line: Int) -> CGFloat? {
        let map = sourceLineMap()
        if let y = map.y(forSourceLine: line) { return y }
        guard mode == .preview else { return nil }
        let anchorLine = parsedPreviewBlocks.first(where: { $0.lines.contains(line) })?.lines.lowerBound ?? line
        guard let visibleLine = nearestVisibleLine(atOrAfter: anchorLine, in: map) else { return nil }
        return map.y(forSourceLine: visibleLine)
    }

    func sourceLine(atY y: CGFloat) -> Int? {
        sourceLineMap().sourceLine(atY: y)
    }

    func sourceLineHeight(forSourceLine line: Int) -> CGFloat? {
        sourceLineMap().height(forSourceLine: line)
    }

    var visibleSourceLines: [Int] {
        sourceLineMap().visibleSourceLines
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = FoldingTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        switch collapseState(for: textElement, layoutManager: textLayoutManager) {
        case .visible:
            break
        case .collapsed:
            fragment.isCollapsed = true
        case .placeholder:
            fragment.isPlaceholder = true
        }
        return fragment
    }

    private enum ElementCollapseState {
        case visible
        case collapsed
        case placeholder
    }

    /// A folded heading collapses fully (no placeholder needed — the next
    /// heading or end of document is the visible boundary). A folded fence
    /// keeps its first hidden line as a placeholder instead of collapsing
    /// it too, so the fence shows its opening line plus a short
    /// placeholder rather than an empty gap (R15). Every other hidden line
    /// in either kind of fold still collapses to zero height, as before —
    /// this only changes what one designated line per folded fence does.
    private func collapseState(for textElement: NSTextElement, layoutManager: NSTextLayoutManager) -> ElementCollapseState {
        guard let elementRange = textElement.elementRange,
              let content = layoutManager.textContentManager
        else {
            return .visible
        }
        let start = content.offset(from: content.documentRange.location, to: elementRange.location)
        let end = content.offset(from: content.documentRange.location, to: elementRange.endLocation)
        let fragmentRange = NSRange(location: start, length: max(0, end - start))
        guard fragmentRange.length > 0 else { return .visible }
        guard isFullyHidden(fragmentRange) else { return .visible }
        return cachedPlaceholderUTF16Locations.contains(start) ? .placeholder : .collapsed
    }

    /// Binary search over `cachedHiddenUTF16Ranges` (sorted ascending by
    /// `location` **and merged into a minimal disjoint set** by
    /// `rebuildHiddenRangesCache`) for a range that fully contains
    /// `fragmentRange` — O(log n) per fragment instead of a linear scan.
    /// The merge step is load-bearing, not cosmetic: a heading's
    /// `foldExtent` spans to the next same-or-shallower heading, so it
    /// necessarily *contains* any nested sub-heading's or fenced code
    /// block's own `foldExtent` — folding an outer block and something
    /// nested inside it at once (two chevron clicks, or Fold All on any
    /// document with nesting) produces overlapping ranges. Without
    /// merging, the "largest start ≤ fragment" candidate can be the
    /// *inner* (nested) range, and a fragment past the inner range's end
    /// but still inside the outer range would wrongly read `.visible` —
    /// a real bug caught in review after this binary search first
    /// landed (see the ticket's Notes). Merging first guarantees no
    /// candidate range is itself nested inside another, so "largest
    /// start ≤ fragment" is correct by construction.
    private func isFullyHidden(_ fragmentRange: NSRange) -> Bool {
        let ranges = cachedHiddenUTF16Ranges
        guard !ranges.isEmpty else { return false }
        var low = 0
        var high = ranges.count - 1
        var candidate = -1
        while low <= high {
            hiddenRangeLookupComparisons += 1
            let mid = (low + high) / 2
            if ranges[mid].location <= fragmentRange.location {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard candidate >= 0 else { return false }
        let hidden = ranges[candidate]
        return NSIntersectionRange(hidden, fragmentRange).length == fragmentRange.length
    }

    var hiddenUTF16RangeCount: Int { cachedHiddenUTF16Ranges.count }

    /// Review fix (T02): if `offset` falls strictly inside a fully
    /// hidden (folded, or a Preview markup-only/continuation range)
    /// UTF-16 range, returns the nearest visible offset in the
    /// direction of travel — the hidden range's end when moving
    /// forward, its start when moving backward — so horizontal caret
    /// movement (`moveHorizontally`) skips over hidden content the same
    /// way point-based click/drag placement and vertical movement
    /// already do (both resolve through `enumeratePackedVisibleFragments`,
    /// which only ever visits non-collapsed fragments). An offset
    /// exactly at a hidden range's boundary is left unchanged — that
    /// position belongs to the adjacent *visible* fragment, not the
    /// hidden one (mirrors `packedCaretRect`'s own inclusive-upperBound
    /// fragment match). Same sorted/merged, binary-searchable
    /// `cachedHiddenUTF16Ranges` `isFullyHidden` already uses — no new
    /// cache, no new cost class.
    func skipHiddenUTF16Offset(_ offset: Int, movingForward: Bool) -> Int {
        let ranges = cachedHiddenUTF16Ranges
        guard !ranges.isEmpty else { return offset }
        var low = 0
        var high = ranges.count - 1
        var candidate = -1
        while low <= high {
            let mid = (low + high) / 2
            if ranges[mid].location <= offset {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard candidate >= 0 else { return offset }
        let hidden = ranges[candidate]
        let hiddenEnd = hidden.location + hidden.length
        guard offset > hidden.location, offset < hiddenEnd else { return offset }
        return movingForward ? hiddenEnd : hidden.location
    }

    private var documentString: String? {
        let string = textStorage?.string
            ?? contentStorage?.textStorage?.string
            ?? (layoutManager?.textContentManager as? NSTextContentStorage)?.textStorage?.string
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    // MARK: - T06: Preview selection → source ranges

    /// The reverse of ticket 08's substitution mapping (which has none
    /// today): for a Preview-mode selection (`selection`, document
    /// UTF-16 coordinates), every touched rendered block's *complete*
    /// source line range, unioned — block-line-grained by design (R22
    /// as written: "copying yields source Markdown," not a byte-exact
    /// mid-block slice).
    ///
    /// Detection and reporting deliberately use different spans. Ticket
    /// 08's substitution collapses every physical line of a multi-line
    /// element *except its first* to zero height (the same mechanism
    /// folding uses, N3) — a table's header/data rows, a wrapped
    /// paragraph's continuation lines — so a click/drag selection can
    /// only ever land on a block's own *anchor* line; that is what
    /// detection checks. Reporting still unions the block's whole
    /// `lines` range, since copying the anchor line alone would silently
    /// drop a table's rows or a wrapped paragraph's later lines. Fenced
    /// code is the one exception in the other direction: ticket 08
    /// leaves a fence's *content* lines to the default pass-through
    /// styling path, un-substituted and genuinely visible one-for-one —
    /// so a selection can land directly on any of a fence's own
    /// physical lines, not just its (collapsed, markup-only) opening
    /// delimiter, and detection uses the fence's whole `Block.lines`
    /// span instead.
    func previewSelectionSourceLineRanges(forUTF16Range selection: NSRange) -> [Range<Int>] {
        guard let lineOffsets = cachedUTF16LineOffsets else { return [] }

        func spanTouchesSelection(_ lines: Range<Int>) -> Bool {
            guard let start = lineOffsets.utf16Offset(ofLine: lines.lowerBound) else { return false }
            let end = lineOffsets.utf16EndOffset(ofLine: lines.upperBound - 1)
            let span = NSRange(location: start, length: max(0, end - start))
            if selection.length == 0 {
                return NSLocationInRange(selection.location, span) || selection.location == span.location + span.length
            }
            return NSIntersectionRange(span, selection).length > 0
        }

        var touched: [Range<Int>] = []
        for block in parsedPreviewBlocks {
            // Fence delimiters are markup-only, always-collapsed anchor
            // lines (ticket 08) — the fence as a whole is handled below,
            // via `blocks`, using its full span instead of just the
            // (unreachable) delimiter line.
            if case .fenceDelimiter = block.kind { continue }
            let anchorLine = block.lines.lowerBound
            guard spanTouchesSelection(anchorLine..<(anchorLine + 1)) else { continue }
            touched.append(block.lines)
        }
        for block in blocks where block.id.kind == .fence {
            guard spanTouchesSelection(block.lines) else { continue }
            touched.append(block.lines)
        }
        return touched
    }

    /// `previewSelectionSourceLineRanges` converted to actual source
    /// Markdown text: each touched line range → raw bytes (via the
    /// cached `SourceMap`), merged into minimal disjoint byte runs
    /// (adjacent/overlapping ranges combined — the common case, since a
    /// Preview drag-selection is visually contiguous top-to-bottom),
    /// each run decoded verbatim, and genuinely separate runs joined
    /// with a blank line. `nil` when the selection touches nothing.
    func previewSelectionSourceMarkdown(forUTF16Range selection: NSRange) -> String? {
        guard let string = documentString, let sourceMap = cachedSourceMap else { return nil }
        let lineRanges = previewSelectionSourceLineRanges(forUTF16Range: selection)
        guard !lineRanges.isEmpty else { return nil }

        let byteRanges = lineRanges.map { lines -> Range<Int> in
            let start = sourceMap.offset(ofLine: lines.lowerBound)
            let end = sourceMap.endOffset(ofLine: lines.upperBound - 1)
            return start..<end
        }.sorted { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        for range in byteRanges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        let scalars = Array(string.utf8)
        let fragments = merged.map { range in
            String(decoding: scalars[range], as: UTF8.self)
        }
        return fragments.joined(separator: "\n")
    }

    /// Recomputes `cachedHiddenUTF16Ranges`/`cachedPlaceholderUTF16Locations`
    /// from their real inputs (`blocks`, `foldStore`'s folded set,
    /// `mode`, `contentStorageDelegate.index`) in one batched pass —
    /// called once from `applyStyling`, not once per fragment. Both
    /// byte→UTF-16 conversions use `UTF8NSRange.nsRanges` (single
    /// forward pass over the document for all needed offsets at once)
    /// rather than looping `UTF8NSRange.nsRange` per block.
    private func rebuildHiddenRangesCache() {
        hiddenRangesCacheRebuildCount += 1
        guard let string = documentString else {
            cachedHiddenUTF16Ranges = []
            cachedPlaceholderUTF16Locations = []
            return
        }

        let hiddenByteRanges = foldStore.hiddenByteRanges(in: blocks)
        var ranges = UTF8NSRange.nsRanges(utf8Bytes: hiddenByteRanges, in: string)
            .filter { $0.location != NSNotFound && $0.length > 0 }
        // Continuation lines of a multi-line Preview substitution (e.g.
        // a table's delimiter/data rows beyond its first line) collapse
        // the same way a folded block does: a zero-height owned
        // fragment (N3), never a rewritten buffer or near-zero font
        // size (N4).
        if mode == .preview, let index = contentStorageDelegate.index {
            ranges.append(contentsOf: index.continuationUTF16Ranges)
        }
        // Sorted, then merged into a minimal disjoint set, so
        // `isFullyHidden` can binary-search instead of linearly
        // scanning every hidden range per fragment. Merging is required
        // for correctness, not just speed — see `isFullyHidden`'s doc.
        cachedHiddenUTF16Ranges = Self.mergedDisjointRanges(ranges.sorted { $0.location < $1.location })

        // A folded fence's opening line gets a placeholder (R15) only
        // when that opening line is not *also* hidden by some other,
        // ancestor fold — a fence's own `foldExtent` never covers its
        // own opening line (it starts right after it), so if
        // `block.bytes.lowerBound` is covered by any hidden range at
        // all, that range can only belong to an ancestor heading. When
        // an ancestor is folded too, the fence's opening line is itself
        // invisible, so nothing about the fence — not even its
        // placeholder — should show (found via review alongside the
        // interval-merge fix above: a document with a folded heading
        // and a folded fence nested inside it previously showed the
        // fence's placeholder line even though its own opening line was
        // already hidden by the heading's fold).
        let placeholderFenceBlocks = blocks.filter { block in
            block.id.kind == .fence && foldStore.isFolded(block.id) && block.foldExtent != nil
        }
        let eligiblePlaceholderBlocks = placeholderFenceBlocks.filter { block in
            !hiddenByteRanges.contains { $0.contains(block.bytes.lowerBound) }
        }
        let placeholderByteRanges = eligiblePlaceholderBlocks.map { block -> Range<Int> in
            let start = block.foldExtent!.lowerBound
            return start..<start
        }
        let placeholderNSRanges = UTF8NSRange.nsRanges(utf8Bytes: placeholderByteRanges, in: string)
        cachedPlaceholderUTF16Locations = Set(placeholderNSRanges.compactMap { $0.location != NSNotFound ? $0.location : nil })
    }

    /// Merges `sorted` (already ascending by `location`) into its
    /// minimal disjoint union via a standard single-pass interval
    /// merge: walk once, extending the last merged range's end whenever
    /// the next range starts at or before it (this also correctly
    /// absorbs a range fully nested inside the last one, since its end
    /// is then also ≤ the last range's end and `max` leaves the end
    /// unchanged). Required so `isFullyHidden`'s binary search — which
    /// assumes no candidate range is itself nested inside another — is
    /// correct for overlapping/nested fold extents (an outer heading's
    /// `foldExtent` containing a nested heading's or fence's own).
    private static func mergedDisjointRanges(_ sorted: [NSRange]) -> [NSRange] {
        guard var current = sorted.first else { return [] }
        var merged: [NSRange] = []
        for range in sorted.dropFirst() {
            let currentEnd = current.location + current.length
            if range.location <= currentEnd {
                let rangeEnd = range.location + range.length
                if rangeEnd > currentEnd {
                    current.length = rangeEnd - current.location
                }
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    /// Rebuilds the Preview substitution index from the cached
    /// (already-parsed) preview structure plus the current theme and
    /// zoom — never re-parses (P3). Deliberately produces data that
    /// lives only on `contentStorageDelegate` — never as attributes on
    /// `textStorage` — so `applyStyling`'s blind
    /// `setAttributes(_:range:)` below cannot clobber it (the
    /// integration risk flagged for this ticket): there is nothing
    /// substitution-related on the buffer to clobber. `applyStyling`
    /// still forces `NSTextContentStorage` to invalidate its cached
    /// paragraphs and re-query this delegate, which is the desired
    /// refresh on every mode/theme/zoom/fold change.
    private func rebuildSubstitutionIndex(textStorage: NSTextStorage) {
        contentStorageDelegate.isPreviewMode = (mode == .preview)
        guard mode == .preview else {
            contentStorageDelegate.index = nil
            return
        }
        let elements = PreviewElementRenderer.render(parsedPreviewBlocks, tokens: tokens, zoomScale: zoomScale)
        contentStorageDelegate.index = PreviewSubstitutionIndex.build(markdown: textStorage.string, elements: elements)
    }

    private func applyStyling(to textStorage: NSTextStorage) {
        rebuildSubstitutionIndex(textStorage: textStorage)
        rebuildHiddenRangesCache()
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        switch mode {
        case .source:
            let source = [
                NSAttributedString.Key.font: PlatformFont.monospaced(size: 14 * zoomScale),
                NSAttributedString.Key.foregroundColor: tokens.body,
            ]
            textStorage.setAttributes(source, range: full)
        case .preview:
            let body = [
                NSAttributedString.Key.font: PlatformFont.body(size: 16 * zoomScale),
                NSAttributedString.Key.foregroundColor: tokens.body,
            ]
            textStorage.setAttributes(body, range: full)
            MarkdownPreviewRenderer.apply(spans: parsedSpans, to: textStorage, tokens: tokens, zoomScale: zoomScale)
        }
        textStorage.endEditing()
    }

    private func invalidateLayout() {
        guard let layoutManager else { return }
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
    }

    private func recountCollapsedFragments() {
        collapsedFragmentCount = 0
        guard let layoutManager else { return }
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            if let folding = fragment as? FoldingTextLayoutFragment, folding.isCollapsed {
                collapsedFragmentCount += 1
            }
            return true
        }
    }

    /// Draws only fragments whose packed position intersects
    /// `visibleRect` (P1): the underlying enumeration still walks from
    /// document start, but stops as soon as `packedY` passes
    /// `visibleRect.maxY` instead of continuing to the end of the
    /// document, and skips the actual `draw` call for anything above
    /// `visibleRect.minY`. `fragmentsEnumeratedLastDraw` counts every
    /// fragment visited (including skipped/collapsed ones) so tests can
    /// assert the walk stays proportional to the viewport, never the
    /// full document.
    func drawFragments(in context: CGContext, visibleRect: CGRect) {
        fragmentsEnumeratedLastDraw = 0
        enumeratePackedVisibleFragments(boundedBy: visibleRect, onVisitFragment: {
            self.fragmentsEnumeratedLastDraw += 1
        }) { fragment, packedY, _ in
            guard packedY + fragment.layoutFragmentFrame.height >= visibleRect.minY else { return }
            fragment.draw(at: CGPoint(x: fragment.layoutFragmentFrame.minX, y: packedY), in: context)
        }
    }

    // MARK: - Point/offset geometry (T01: caret placement, mouse click,
    // NSTextInputClient's characterIndex(for:)/firstRect(forCharacterRange:))

    /// Resolves `point` — in the same packed coordinate space
    /// `drawFragments` draws into (x already gutter-adjusted by the
    /// caller; y already "packed," skipping the extra space folded/
    /// collapsed fragments would otherwise leave in TextKit's own raw
    /// geometry) — to the nearest UTF-16 document offset. There is no
    /// existing point↔offset helper anywhere in this codebase (T01);
    /// built from `NSTextLayoutFragment.textLineFragments`/
    /// `NSTextLineFragment.characterIndex(for:)` composed with the same
    /// packed-Y fragment walk `drawFragments` already uses, since raw
    /// TextKit geometry does not skip hidden/folded content on its own.
    /// `visibleRect`, when non-nil, bounds the walk the same way
    /// `drawFragments` does (P1) — mouse click/drag is a continuous,
    /// per-frame interaction and must not become O(document).
    func utf16Offset(atPackedPoint point: CGPoint, boundedBy visibleRect: CGRect? = nil) -> Int? {
        var resolved: Int?
        var lastSeenEnd: Int?
        enumeratePackedVisibleFragments(boundedBy: visibleRect) { fragment, packedY, utf16Range in
            guard resolved == nil else { return }
            let height = fragment.layoutFragmentFrame.height
            lastSeenEnd = utf16Range.upperBound
            guard point.y >= packedY, point.y < packedY + max(height, 1) else { return }
            let local = CGPoint(x: point.x, y: point.y - packedY)
            resolved = Self.characterOffset(inPackedFragment: fragment, at: local, elementStartUTF16: utf16Range.location)
        }
        if let resolved { return resolved }
        // Below every visible fragment (or the point is past the last
        // one considered): clamp to the end of the last fragment seen,
        // matching a standard text view's "click past the last line
        // places the caret at the very end" behavior.
        if let lastSeenEnd { return lastSeenEnd }
        // No fragment was visited at all — a brand-new, still-empty
        // document has nothing for TextKit 2 to lay out yet, so there's
        // nothing to hit-test against. The only sensible offset for an
        // empty buffer is 0; without this, a click on a new document
        // resolved to `nil`, `mouseDown` fell through to
        // `super.mouseDown(with:)`, and the caret could never be placed
        // (surfacing as an alert beep on any click attempt).
        return (textStorage?.length ?? 0) == 0 ? 0 : nil
    }

    private static func characterOffset(inPackedFragment fragment: NSTextLayoutFragment, at localPoint: CGPoint, elementStartUTF16: Int) -> Int {
        let lineFragments = fragment.textLineFragments
        guard !lineFragments.isEmpty else { return elementStartUTF16 }
        var cumulative = 0
        for (index, lineFragment) in lineFragments.enumerated() {
            let bounds = lineFragment.typographicBounds
            let isLast = index == lineFragments.count - 1
            if localPoint.y <= bounds.maxY || isLast {
                let rawIndex = lineFragment.characterIndex(for: localPoint)
                let clamped = max(0, min(rawIndex, lineFragment.characterRange.length))
                return elementStartUTF16 + cumulative + clamped
            }
            cumulative += lineFragment.characterRange.length
        }
        return elementStartUTF16 + cumulative
    }

    /// The inverse of `utf16Offset(atPackedPoint:boundedBy:)`: the
    /// packed-coordinate-space caret rect (a thin, full-line-height
    /// rect) for `offset` — used both for drawing the blinking caret
    /// and for `NSTextInputClient.firstRect(forCharacterRange:actualRange:)`.
    /// Returns `nil` when `offset` does not resolve to any visible
    /// (non-hidden, non-folded) fragment within `visibleRect` — the same
    /// skip-hidden-content behavior `drawFragments` already has, since
    /// collapsed fragments are never handed to the enumeration body.
    func packedCaretRect(forUTF16Offset offset: Int, boundedBy visibleRect: CGRect? = nil) -> CGRect? {
        var result: CGRect?
        enumeratePackedVisibleFragments(boundedBy: visibleRect) { fragment, packedY, utf16Range in
            guard result == nil else { return }
            guard offset >= utf16Range.location, offset <= utf16Range.upperBound else { return }
            result = Self.caretRect(inPackedFragment: fragment, atUTF16Offset: offset, elementStartUTF16: utf16Range.location, packedY: packedY)
        }
        if let result { return result }
        // Same empty-document gap as `utf16Offset(atPackedPoint:)`: no
        // fragment exists yet to anchor offset 0 to, so without this the
        // caret could never be drawn at all on a brand-new document —
        // not even before any click, which is why a new document didn't
        // already show a placed caret the way it should.
        guard offset == 0, (textStorage?.length ?? 0) == 0 else { return nil }
        let font = PlatformFont.monospaced(size: 14 * zoomScale)
        let lineHeight = max(font.ascender - font.descender + font.leading, 1)
        return CGRect(x: 0, y: 0, width: 2, height: lineHeight)
    }

    private static func caretRect(inPackedFragment fragment: NSTextLayoutFragment, atUTF16Offset offset: Int, elementStartUTF16: Int, packedY: CGFloat) -> CGRect {
        let lineFragments = fragment.textLineFragments
        guard !lineFragments.isEmpty else {
            return CGRect(x: 0, y: packedY, width: 2, height: max(fragment.layoutFragmentFrame.height, 1))
        }
        var cumulative = elementStartUTF16
        for (index, lineFragment) in lineFragments.enumerated() {
            let lineEnd = cumulative + lineFragment.characterRange.length
            let isLast = index == lineFragments.count - 1
            if offset <= lineEnd || isLast {
                let localIndex = max(0, min(offset - cumulative, lineFragment.characterRange.length))
                let point = lineFragment.locationForCharacter(at: localIndex)
                let bounds = lineFragment.typographicBounds
                return CGRect(x: point.x, y: packedY + bounds.minY, width: 2, height: max(bounds.height, 1))
            }
            cumulative = lineEnd
        }
        let bounds = lineFragments[lineFragments.count - 1].typographicBounds
        return CGRect(x: 0, y: packedY + bounds.minY, width: 2, height: max(bounds.height, 1))
    }

    /// T02: one packed-coordinate-space rect per line the selection
    /// touches (a real range typically spans several `NSTextLineFragment`s
    /// once it crosses a wrapped line or a fragment boundary) — the
    /// selection-highlight counterpart of `packedCaretRect`. Empty for a
    /// zero-length range (nothing to highlight; that's the caret's job).
    /// `visibleRect`, when non-nil, bounds the walk the same way
    /// `drawFragments`/the caret helpers do (P1) — drag-selection is a
    /// continuous, per-frame interaction.
    func packedSelectionRects(forUTF16Range range: NSRange, boundedBy visibleRect: CGRect? = nil) -> [CGRect] {
        guard range.length > 0 else { return [] }
        var rects: [CGRect] = []
        enumeratePackedVisibleFragments(boundedBy: visibleRect) { fragment, packedY, utf16Range in
            let intersection = NSIntersectionRange(utf16Range, range)
            guard intersection.length > 0 else { return }
            rects.append(contentsOf: Self.selectionRects(inPackedFragment: fragment, intersecting: intersection, elementStartUTF16: utf16Range.location, packedY: packedY))
        }
        return rects
    }

    private static func selectionRects(inPackedFragment fragment: NSTextLayoutFragment, intersecting range: NSRange, elementStartUTF16: Int, packedY: CGFloat) -> [CGRect] {
        let lineFragments = fragment.textLineFragments
        guard !lineFragments.isEmpty else { return [] }
        var rects: [CGRect] = []
        var cumulative = elementStartUTF16
        for lineFragment in lineFragments {
            let lineRange = NSRange(location: cumulative, length: lineFragment.characterRange.length)
            let intersection = NSIntersectionRange(lineRange, range)
            if intersection.length > 0 {
                let startLocal = max(0, min(lineFragment.characterRange.length, intersection.location - cumulative))
                let endLocal = max(0, min(lineFragment.characterRange.length, intersection.location + intersection.length - cumulative))
                let startPoint = lineFragment.locationForCharacter(at: startLocal)
                let endPoint = lineFragment.locationForCharacter(at: endLocal)
                let bounds = lineFragment.typographicBounds
                let minX = min(startPoint.x, endPoint.x)
                let maxX = max(startPoint.x, endPoint.x)
                rects.append(CGRect(x: minX, y: packedY + bounds.minY, width: max(maxX - minX, 1), height: max(bounds.height, 1)))
            }
            cumulative += lineFragment.characterRange.length
        }
        return rects
    }

    private func packedLayoutHeight() -> CGFloat {
        var height: CGFloat = 0
        enumeratePackedVisibleFragments { fragment, _, _ in
            height += fragment.layoutFragmentFrame.height
        }
        return height
    }

    private struct PackedFragment {
        var fragment: NSTextLayoutFragment
        var utf16Range: NSRange
        var packedY: CGFloat
    }

    /// `visibleRect`, when non-nil, bounds the walk: enumeration stops
    /// once accumulated `packedY` passes `visibleRect.maxY` rather than
    /// continuing to the document's end (P1). `onVisitFragment`, when
    /// provided, is called once per fragment the underlying
    /// `enumerateTextLayoutFragments` visits — including fragments
    /// skipped for being collapsed — so callers can count the true
    /// walk size independent of what `body` chooses to act on.
    private func enumeratePackedVisibleFragments(
        boundedBy visibleRect: CGRect? = nil,
        onVisitFragment: (() -> Void)? = nil,
        _ body: (NSTextLayoutFragment, CGFloat, NSRange) -> Void
    ) {
        guard let layoutManager, let content = layoutManager.textContentManager else { return }
        var packedY: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            onVisitFragment?()
            let collapsed = (fragment as? FoldingTextLayoutFragment)?.isCollapsed ?? false
            if !collapsed {
                let utf16 = utf16Range(for: fragment, content: content)
                body(fragment, packedY, utf16)
                packedY += fragment.layoutFragmentFrame.height
            }
            if let visibleRect, packedY > visibleRect.maxY {
                return false
            }
            return true
        }
    }

    private func packedVisibleFragments(boundedBy visibleRect: CGRect? = nil) -> [PackedFragment] {
        var packed: [PackedFragment] = []
        enumeratePackedVisibleFragments(boundedBy: visibleRect) { fragment, packedY, utf16 in
            packed.append(PackedFragment(fragment: fragment, utf16Range: utf16, packedY: packedY))
        }
        return packed
    }

    private func utf16Range(for fragment: NSTextLayoutFragment, content: NSTextContentManager) -> NSRange {
        let range = fragment.rangeInElement
        let start = content.offset(from: content.documentRange.location, to: range.location)
        let end = content.offset(from: content.documentRange.location, to: range.endLocation)
        return NSRange(location: start, length: max(0, end - start))
    }

    /// `visibleRect`, when non-nil, bounds both the fragment walk
    /// (reusing T01's `enumeratePackedVisibleFragments(boundedBy:)`)
    /// and the source-line scan to just the lines the visible packed
    /// fragments span — found via two binary searches into the cached
    /// `UTF16LineOffsets` (O(log lines)), never a scan of every line in
    /// the document (P2). When nil, behavior is unchanged from before
    /// this ticket: every source line is examined against the
    /// (unbounded) packed-fragment list.
    private func packedSourceLineEntries(boundedBy visibleRect: CGRect? = nil) -> [SourceLineMap.Entry] {
        guard let string = documentString else { return [] }

        let sourceMap = cachedSourceMap ?? SourceMap(markdown: string)
        let hidden = cachedHiddenUTF16Ranges
        let packed = packedVisibleFragments(boundedBy: visibleRect)
        var entries: [SourceLineMap.Entry] = []
        sourceLinesScannedLastGutterCompute = 0

        let lineRangeToScan: ClosedRange<Int>
        if let visibleRect {
            guard let lineOffsets = cachedUTF16LineOffsets,
                  let first = packed.first,
                  let last = packed.last
            else { return [] }
            let firstLine = max(1, lineOffsets.lineNumber(atUTF16Offset: first.utf16Range.location))
            let lastOffset = max(last.utf16Range.location, last.utf16Range.upperBound - 1)
            let lastLine = min(sourceMap.lineStarts.count, lineOffsets.lineNumber(atUTF16Offset: lastOffset))
            guard firstLine <= lastLine else { return [] }
            lineRangeToScan = firstLine...lastLine
        } else {
            guard sourceMap.lineStarts.count > 0 else { return [] }
            lineRangeToScan = 1...sourceMap.lineStarts.count
        }

        for line in lineRangeToScan {
            sourceLinesScannedLastGutterCompute += 1
            let bytes = sourceMap.offset(ofLine: line)..<sourceMap.endOffset(ofLine: line)
            let lineRange = UTF8NSRange.nsRange(utf8Bytes: bytes, in: string)
            guard lineRange.location != NSNotFound else { continue }
            if isHidden(lineRange: lineRange, hidden: hidden) { continue }
            guard let host = packed.first(where: { NSLocationInRange(lineRange.location, $0.utf16Range) || ($0.utf16Range.length == 0 && $0.utf16Range.location == lineRange.location) })
                    ?? packed.first(where: { NSIntersectionRange($0.utf16Range, lineRange).length > 0 })
            else { continue }

            let relative = sourceLineMetrics(lineRange: lineRange, in: host)
            entries.append(
                SourceLineMap.Entry(
                    sourceLine: line,
                    y: host.packedY + relative.y,
                    height: relative.height
                )
            )
        }
        return entries
    }

    private func isHidden(lineRange: NSRange, hidden: [NSRange]) -> Bool {
        if lineRange.length == 0 {
            return hidden.contains { NSLocationInRange(lineRange.location, $0) }
        }
        return hidden.contains { hiddenRange in
            NSIntersectionRange(hiddenRange, lineRange).length == lineRange.length
        }
    }

    private func sourceLineMetrics(lineRange: NSRange, in host: PackedFragment) -> (y: CGFloat, height: CGFloat) {
        let fragment = host.fragment
        let lineFragments = fragment.textLineFragments
        guard !lineFragments.isEmpty else {
            return (0, fragment.layoutFragmentFrame.height)
        }

        let fragmentStart = host.utf16Range.location
        var matching: [NSTextLineFragment] = []
        var cursor = fragmentStart
        for lineFragment in lineFragments {
            let lfRange = NSRange(location: cursor, length: lineFragment.characterRange.length)
            if NSIntersectionRange(lfRange, lineRange).length > 0 || (lineRange.length == 0 && NSLocationInRange(lineRange.location, lfRange)) {
                matching.append(lineFragment)
            }
            cursor += lineFragment.characterRange.length
        }

        if matching.isEmpty {
            let onlyLineInFragment = host.utf16Range.length > 0
                && NSIntersectionRange(host.utf16Range, lineRange).length == min(lineRange.length, host.utf16Range.length)
            if onlyLineInFragment || lineFragments.count == 1 {
                return (0, fragment.layoutFragmentFrame.height)
            }
            return (0, lineFragments[0].typographicBounds.height)
        }

        let minY = matching.map(\.typographicBounds.minY).min() ?? 0
        let maxY = matching.map { $0.typographicBounds.maxY }.max() ?? minY
        let height = max(maxY - minY, matching.last?.typographicBounds.height ?? 0)
        return (minY, height)
    }
}

enum PlatformFont {
    static func monospaced(size: CGFloat) -> PlatformFontType {
        #if os(macOS)
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #endif
    }

    static func body(size: CGFloat) -> PlatformFontType {
        #if os(macOS)
        NSFont.systemFont(ofSize: size)
        #else
        UIFont.systemFont(ofSize: size)
        #endif
    }

    static func heading(size: CGFloat) -> PlatformFontType {
        #if os(macOS)
        NSFont.boldSystemFont(ofSize: size)
        #else
        UIFont.boldSystemFont(ofSize: size)
        #endif
    }

    /// `base` with italic added to its existing traits, same point size.
    static func italic(_ base: PlatformFontType) -> PlatformFontType {
        #if os(macOS)
        NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        #else
        let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitItalic)) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: base.pointSize)
        #endif
    }

    /// `base` with bold added to its existing traits, same point size.
    static func bold(_ base: PlatformFontType) -> PlatformFontType {
        #if os(macOS)
        NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        #else
        let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitBold)) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: base.pointSize)
        #endif
    }

    static func isItalic(_ font: PlatformFontType) -> Bool {
        #if os(macOS)
        font.fontDescriptor.symbolicTraits.contains(.italic)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    static func isBold(_ font: PlatformFontType) -> Bool {
        #if os(macOS)
        font.fontDescriptor.symbolicTraits.contains(.bold)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }
}

enum PlatformColor {
    static var label: PlatformColorType {
        #if os(macOS)
        NSColor.labelColor
        #else
        UIColor.label
        #endif
    }

    static var secondaryLabel: PlatformColorType {
        #if os(macOS)
        NSColor.secondaryLabelColor
        #else
        UIColor.secondaryLabel
        #endif
    }

    /// T02: the selection highlight fill — the standard system
    /// selected-text color on macOS (matches every other AppKit text
    /// view rather than inventing a theme-specific one; `ThemeTokens`
    /// has no selection field of its own).
    static var selectionHighlight: PlatformColorType {
        #if os(macOS)
        NSColor.selectedTextBackgroundColor
        #else
        UIColor.systemBlue.withAlphaComponent(0.3)
        #endif
    }
}

enum GutterMetrics {
    static let chevronWidth: CGFloat = 16
    static let numberWidth: CGFloat = 36

    static func width(showLineNumbers: Bool) -> CGFloat {
        if showLineNumbers {
            return chevronWidth + numberWidth
        }
        return chevronWidth
    }
}

#if os(macOS)
typealias PlatformFontType = NSFont
typealias PlatformColorType = NSColor
typealias PlatformView = NSView
#else
typealias PlatformFontType = UIFont
typealias PlatformColorType = UIColor
typealias PlatformView = UIView
#endif

#if os(macOS)
/// T02: what unit a mouse drag extends the selection by, set once at
/// `mouseDown` from the click count (single/double/triple-click).
enum DragSelectionMode {
    case character
    case word
    case line
}

/// T03: the class of single-character edit a coalescable mutation
/// belongs to — inserts only coalesce with inserts, backward deletes
/// only with backward deletes, forward deletes only with forward
/// deletes (never mixed), matching the plan's "consecutive single-
/// character insertText calls (and consecutive single-character
/// deletes)" wording.
enum CoalescingKind: Equatable {
    case insert
    case deleteBackward
    case deleteForward
}
#endif

/// T04: which of `NSDocument.ChangeType`'s three text-editing cases a
/// committed buffer mutation corresponds to — kept AppKit-free (not
/// `NSDocument.ChangeType` itself) so `FoldingTextView`'s cross-platform
/// surface (this callback is declared unconditionally, even though only
/// macOS's `NSTextInputClient` path and `MarkdownDocument` consume it
/// today) doesn't need to import AppKit. `MarkdownDocument` maps this
/// to the real `NSDocument.ChangeType` and calls `updateChangeCount`.
enum TextChangeKind: Sendable {
    case done
    case undone
    case redone
}

@MainActor
final class FoldingTextView: PlatformView {
    let session: FoldingSession
    let contentStorage: NSTextContentStorage
    let textLayoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer
    let documentTextStorage: NSTextStorage
    private let editingUndoManager = UndoManager()
    #if os(macOS)
    /// T01: the blinking caret's current on/off phase, and the marked
    /// (IME/dictation composing) UTF-16 range, if any. Both are
    /// macOS-only — `NSTextInputClient`/mouse-driven selection are
    /// AppKit-only per the ticket's Design note; iOS/iPadOS keep
    /// building and passing the existing non-editing suite (N6) with no
    /// new editing behaviour required.
    private var caretBlinkTimer: Timer?
    private(set) var caretVisible: Bool = true
    private var markedTextUTF16Range: NSRange?
    /// The buffer text `markedTextUTF16Range` is standing in for, as it
    /// was immediately before the current IME/dictation composing
    /// session began (captured once, on the first `setMarkedText` call
    /// of a session) — see `mutateSourceText`'s `undoPreviousOverride`.
    private var composingOriginalText: String?
    /// T02: the fixed end of an in-progress keyboard (Shift+arrow)
    /// selection extension — `nil` whenever no extension is active (a
    /// plain arrow key, a fresh click, or a mutation collapses it).
    private var selectionAnchorOffset: Int?
    /// T02: the fixed end of an in-progress mouse drag selection, and
    /// what kind of unit (character/word/line) the drag extends by —
    /// set on `mouseDown`, read by `mouseDragged`, cleared on `mouseUp`.
    private var dragAnchorOffset: Int?
    private var dragAnchorMode: DragSelectionMode = .character
    /// T03: the kind and end-position of the most recent coalescable
    /// single-character edit, and when it happened — used by
    /// `applyCoalescingGrouping` to decide whether the next edit
    /// continues the same open `editingUndoManager` group (one undo
    /// step for a whole typed run) or starts a fresh one. `nil` kind
    /// means "nothing open should be extended" (a paste, a multi-
    /// character insert, an IME commit, or an undo/redo replay).
    private var coalescingKind: CoalescingKind?
    private var coalescingCaretOffset: Int?
    private var coalescingLastEditAt: Date = .distantPast
    /// Injectable so tests can simulate a long pause between keystrokes
    /// deterministically (N9) instead of sleeping for real wall-clock
    /// time.
    var coalescingClock: () -> Date = { Date() }
    /// T05: the pending debounced `session.syncBlocksFromStorage()`
    /// call — cancelled and rescheduled on every keystroke so a burst
    /// of typing reparses once, after a quiet period, rather than once
    /// per character.
    private var reparseDebounceTimer: Timer?
    #endif

    var foldStore: FoldStore { session.foldStore }
    var blocks: [Block] { session.blocks }
    var layoutHeight: CGFloat { session.layoutHeight }
    var collapsedFragmentCount: Int { session.collapsedFragmentCount }
    var hiddenRangeCount: Int { session.hiddenUTF16RangeCount }
    var textStorage: NSTextStorage? { documentTextStorage }
    var visibleSourceLines: [Int] { session.visibleSourceLines }

    func y(forSourceLine line: Int) -> CGFloat? {
        session.y(forSourceLine: line)
    }

    func sourceLine(atY y: CGFloat) -> Int? {
        session.sourceLine(atY: y)
    }

    func sourceLineHeight(forSourceLine line: Int) -> CGFloat? {
        session.sourceLineHeight(forSourceLine: line)
    }

    #if os(macOS)
    var showLineNumbers: Bool {
        get { true }
        set { _ = newValue }
    }
    #else
    var showLineNumbers: Bool = true {
        didSet { updateTextContainerForGutter() }
    }
    #endif

    var gutterWidth: CGFloat {
        GutterMetrics.width(showLineNumbers: showLineNumbers)
    }

    /// The live, testable proxy for what the gutter actually draws (N9).
    /// Source mode: unchanged, one number per visible source line. Preview
    /// mode: one number per rendered block's true start (R13) — the
    /// number itself is always the block's real anchor line, but a block
    /// only appears here if that anchor (or, when the anchor is itself
    /// invisible markup, the nearest visible line after it — see
    /// `FoldingSession.nearestVisibleLine`) actually resolves to
    /// something on screen.
    func gutterLineNumbers() -> [Int] {
        guard showLineNumbers else { return [] }
        guard mode == .preview else { return visibleSourceLines }
        let map = session.sourceLineMap()
        return session.previewBlockAnchorLines
            .filter { session.nearestVisibleLine(atOrAfter: $0, in: map) != nil }
            .sorted()
    }

    /// Every foldable block's true anchor line (`FoldID.startLine`),
    /// filtered to those that resolve to a visible on-screen position —
    /// directly, or (Preview only) via `FoldingSession.nearestVisibleLine`
    /// when the block's own start line is itself invisible markup (a
    /// fence's opening delimiter, always; an empty heading, sometimes).
    /// Reported values are always the block's real start line, never the
    /// resolved display line, so callers (fold toggling, tests) keep
    /// keying folds by their true anchor.
    func foldableSourceLines() -> [Int] {
        let map = session.sourceLineMap()
        return blocks.compactMap { block in
            guard block.foldExtent != nil,
                  session.nearestVisibleLine(atOrAfter: block.id.startLine, in: map) != nil
            else { return nil }
            return block.id.startLine
        }
    }

    func toggleFold(atSourceLine line: Int) {
        guard let block = blocks.first(where: { $0.id.startLine == line && $0.foldExtent != nil }) else { return }
        foldStore.toggle(block.id)
        applyFolds()
        ensureLayout()
        // The real chevron-click path (`handleGutterClick`) reaches this
        // method directly, bypassing DocumentHost/DocumentSession — so
        // this is the one place that can reliably notify dependents (the
        // minimap among them) that a fold changed (G.19).
        onTextDidChange?()
    }

    func jumpToSourceLine(_ line: Int) {
        ensureLayout()
        let markdown = documentTextStorage.string
        guard line >= 1 else { return }
        let map = SourceMap(markdown: markdown)
        guard line <= map.lineStarts.count else { return }
        let start = map.offset(ofLine: line)
        let end = min(start + 1, map.byteCount)
        let range = UTF8NSRange.nsRange(utf8Bytes: start..<max(start, end), in: markdown)
        if range.location != NSNotFound {
            selectedUTF16Range = NSRange(location: range.location, length: 0)
        }
        lastJumpedPackedY = y(forSourceLine: line)
        if let packedY = lastJumpedPackedY {
            scrollPackedYOnScreen(packedY)
        }
    }

    private(set) var scrollOrigin = CGPoint.zero

    func viewportContainsPackedY(_ y: CGFloat) -> Bool {
        let vis = visiblePackedRect()
        return y >= vis.minY && y <= vis.maxY
    }

    /// The packed-layout rect currently on screen, in the same packed
    /// coordinate space as `SourceLineMap`/`layoutHeight` — used by the
    /// minimap to draw a viewport indicator (R18).
    func currentVisiblePackedRect() -> CGRect {
        visiblePackedRect()
    }

    func scrollPackedYOnScreen(_ packedY: CGFloat) {
        let lineHeight = sourceLineHeight(forSourceLine: sourceLine(atY: packedY) ?? 1) ?? 20
        let target = CGRect(x: 0, y: packedY, width: max(bounds.width, 1), height: max(lineHeight, 1))
        #if os(macOS)
        if let scroll = enclosingScrollView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: packedY))
            scroll.reflectScrolledClipView(scroll.contentView)
            if !scroll.documentVisibleRect.intersects(target) {
                scrollToVisible(target)
            }
            scrollOrigin = CGPoint(x: 0, y: scroll.documentVisibleRect.minY)
            return
        }
        #else
        if let scroll = enclosingPlatformScrollView {
            let visibleHeight = max(scroll.bounds.height, 1)
            let contentHeight = max(scroll.contentSize.height, layoutHeight, visibleHeight)
            let maxOrigin = max(0, contentHeight - visibleHeight)
            let originY = min(max(0, packedY), maxOrigin)
            scroll.setContentOffset(CGPoint(x: 0, y: originY), animated: false)
            scrollOrigin = scroll.contentOffset
            return
        }
        #endif
        let visibleHeight = max(bounds.height, 1)
        let contentHeight = max(layoutHeight, visibleHeight)
        let maxOrigin = max(0, contentHeight - visibleHeight)
        var originY = min(max(0, packedY), maxOrigin)
        if packedY < originY {
            originY = max(0, packedY)
        }
        scrollOrigin = CGPoint(x: 0, y: originY)
    }

    private func visiblePackedRect() -> CGRect {
        #if os(macOS)
        if let scroll = enclosingScrollView {
            return scroll.documentVisibleRect
        }
        #else
        if let scroll = enclosingPlatformScrollView {
            return CGRect(origin: scroll.contentOffset, size: scroll.bounds.size)
        }
        #endif
        return CGRect(origin: scrollOrigin, size: bounds.size)
    }

    #if os(iOS)
    private var enclosingPlatformScrollView: UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            view = current.superview
        }
        return nil
    }
    #endif

    @discardableResult
    func find(_ query: String) -> NSRange? {
        let found = FindReplace.search(query, in: documentTextStorage, from: selectedUTF16Range.location)
        if let found {
            selectedUTF16Range = found
        }
        return found
    }

    @discardableResult
    func replaceSelection(with replacement: String) -> Bool {
        let ok = FindReplace.replace(selectedUTF16Range, with: replacement, in: documentTextStorage)
        if ok {
            session.syncBlocksFromStorage()
            onTextDidChange?()
            onTextChangeCommitted?(currentTextChangeKind)
        }
        return ok
    }

    func syncBlocksFromStorage() {
        session.syncBlocksFromStorage()
    }

    func restoreFolds(for url: URL?) {
        session.restoreFolds(for: url)
        ensureLayout()
    }

    var string: String {
        get { documentTextStorage.string }
        set { loadMarkdown(newValue) }
    }
    var onTextDidChange: (() -> Void)?
    /// T04: fires alongside `onTextDidChange` for every *text-buffer*
    /// mutation specifically (not fold/theme/zoom/mode changes, which
    /// call `onTextDidChange` for SwiftUI re-publishing but never touch
    /// the buffer) — `MarkdownDocument` sets this to call
    /// `self.updateChangeCount(_:)` with the right `NSDocument
    /// .ChangeType` (R21). Kept separate from `onTextDidChange` rather
    /// than folding a kind parameter into it, since `DocumentSession`
    /// already owns that callback for its own (unrelated) purpose and
    /// this ticket's Design note explicitly calls for "a second
    /// callback."
    var onTextChangeCommitted: ((TextChangeKind) -> Void)?
    /// The kind of text change currently being committed, determined
    /// from `editingUndoManager.isUndoing`/`.isRedoing` at the moment a
    /// mutation completes — real `UndoManager` properties, not manually
    /// threaded kind information through every call site (per the
    /// ticket's Design note).
    private var currentTextChangeKind: TextChangeKind {
        if editingUndoManager.isUndoing { return .undone }
        if editingUndoManager.isRedoing { return .redone }
        return .done
    }
    var selectedUTF16Range = NSRange(location: 0, length: 0)
    var lastJumpedPackedY: CGFloat?
    var mode: EditorMode { session.mode }
    var tokens: ThemeTokens { session.tokens }
    var zoomScale: CGFloat { session.zoomScale }
    var canvasBackground: PlatformColorType { session.tokens.background }
    #if os(macOS)
    var ignoresHits = false
    #endif

    func configureAsThemeProxy() {
        #if os(macOS)
        ignoresHits = true
        #else
        isUserInteractionEnabled = false
        #endif
    }

    convenience init(foldStore: FoldStore = FoldStore()) {
        self.init(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: foldStore)
    }

    init(frame: CGRect, foldStore: FoldStore) {
        contentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer(size: CGSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        documentTextStorage = NSTextStorage()
        session = FoldingSession(foldStore: foldStore)
        super.init(frame: frame)
        completeInit()
    }

    override init(frame: CGRect) {
        contentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer(size: CGSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        documentTextStorage = NSTextStorage()
        session = FoldingSession()
        super.init(frame: frame)
        completeInit()
    }

    required init?(coder: NSCoder) {
        contentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer(size: CGSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        documentTextStorage = NSTextStorage()
        session = FoldingSession()
        super.init(coder: coder)
        completeInit()
    }

    private func completeInit() {
        textLayoutManager.textContainer = textContainer
        contentStorage.addTextLayoutManager(textLayoutManager)
        contentStorage.textStorage = documentTextStorage
        session.attach(layoutManager: textLayoutManager, contentStorage: contentStorage)
        updateTextContainerForGutter()
        paintCanvasBackground()
        // T03: `editingUndoManager` groups every coalescable keystroke
        // run explicitly (`applyCoalescingGrouping`'s own begin/end
        // pairs) — `groupsByEvent`'s default `true` also auto-opens an
        // *additional*, nested implicit group around each run-loop-
        // observed "event" whenever `registerUndo` is called, on top of
        // any explicit group already open. Found via a real crash/bug
        // hunt (not guessed): tracing `groupingLevel` around every
        // begin/end call showed it jumping straight to 2 on the very
        // first keystroke of a fresh group, not 1 — the explicit
        // "close one level, then reopen" logic in
        // `applyCoalescingGrouping` only ever closed the automatic
        // inner layer, never reaching the true outer boundary, so every
        // "new" group after the first kept nesting inside the original
        // one instead of standing alone — `undo()` then reverted every
        // keystroke ever made in the test, not just the most recent
        // group. Disabling `groupsByEvent` (its own documented escape
        // hatch for "I manage grouping myself") removes the automatic
        // layer entirely, leaving only the explicit grouping in control.
        editingUndoManager.groupsByEvent = false
    }

    private func paintCanvasBackground() {
        #if os(macOS)
        wantsLayer = true
        layer?.backgroundColor = session.tokens.background.cgColor
        needsDisplay = true
        #else
        backgroundColor = session.tokens.background
        isOpaque = true
        setNeedsDisplay()
        #endif
    }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { !ignoresHits }
    override var undoManager: UndoManager? { editingUndoManager }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if ignoresHits { return nil }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        session.tokens.background.setFill()
        dirtyRect.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawGutter(in: context, visibleRect: dirtyRect)
        context.saveGState()
        context.translateBy(x: gutterWidth, y: 0)
        drawSelectionHighlight(in: context, visibleRect: dirtyRect)
        session.drawFragments(in: context, visibleRect: dirtyRect)
        context.restoreGState()
        drawCaret(in: context)
    }

    override func layout() {
        super.layout()
        updateTextContainerForGutter()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleGutterClick(at: point) { return }
        // T06: Preview stays read-only (insertText/doCommand/
        // setMarkedText all still gate on `.source` independently) but
        // must remain *selectable* (R22) — click/drag selection
        // mechanics themselves are mode-agnostic (the same point↔offset
        // helpers, word/line range detection), so both modes fall
        // through to them; only actual mutation stays source-only.
        window?.makeFirstResponder(self)
        guard let offset = utf16Offset(forViewPoint: point) else {
            super.mouseDown(with: event)
            return
        }
        selectionAnchorOffset = nil
        switch event.clickCount {
        case 2:
            let range = wordRange(at: offset)
            selectedUTF16Range = range
            dragAnchorOffset = range.location
            dragAnchorMode = .word
        case 3...:
            let range = lineRange(at: offset)
            selectedUTF16Range = range
            dragAnchorOffset = range.location
            dragAnchorMode = .line
        default:
            selectedUTF16Range = NSRange(location: offset, length: 0)
            dragAnchorOffset = offset
            dragAnchorMode = .character
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        // T06: drag-selection is mode-agnostic too (see `mouseDown`'s
        // comment) — `dragAnchorOffset` is only ever set by `mouseDown`,
        // so this naturally no-ops whenever that didn't start a drag.
        guard let anchor = dragAnchorOffset else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let offset = utf16Offset(forViewPoint: point) else { return }
        switch dragAnchorMode {
        case .character:
            selectedUTF16Range = normalizedRange(anchor, offset)
        case .word:
            let word = wordRange(at: offset)
            selectedUTF16Range = normalizedRange(min(anchor, word.location), max(anchor, word.location + word.length))
        case .line:
            let line = lineRange(at: offset)
            selectedUTF16Range = normalizedRange(min(anchor, line.location), max(anchor, line.location + line.length))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchorOffset = nil
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // T06: Cmd+C must work in Preview mode too (R22 "selectable...
        // copying yields source Markdown") — checked before the
        // Source-only gate below, since `copy(_:)` itself branches on
        // mode to produce the right pasteboard content either way.
        // Everything else here (character/command input via
        // `interpretKeyEvents`) stays Source-only; Preview never
        // mutates.
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            copy(nil)
            return
        }
        // Review fix: undo/redo were only reachable programmatically —
        // R20 says plainly "undo and redo work," and as shipped a
        // person typing in Markus had no way to undo a typo (no Edit >
        // Undo/Redo menu item exists either, per R3's explicit item
        // list). Same precedent as Cmd+C just above: Cmd+letter
        // combinations aren't part of AppKit's default text key-binding
        // table, so this is checked explicitly, ahead of the Source-only
        // gate — undo/redo must keep working even after switching to
        // Preview mid-edit, matching `undoLastChange`/`redoLastChange`'s
        // own mode-independence.
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                redoLastChange()
            } else {
                undoLastChange()
            }
            return
        }
        guard session.mode == .source else {
            super.keyDown(with: event)
            return
        }
        interpretKeyEvents([event])
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, session.mode == .source {
            startCaretBlinking()
        }
        return became
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        stopCaretBlinking()
        return super.resignFirstResponder()
    }
    #else
    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { editingUndoManager }

    override func draw(_ rect: CGRect) {
        backgroundColor?.setFill()
        UIRectFill(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawGutter(in: context, visibleRect: rect)
        context.saveGState()
        context.translateBy(x: gutterWidth, y: 0)
        session.drawFragments(in: context, visibleRect: rect)
        context.restoreGState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextContainerForGutter()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self), handleGutterClick(at: point) {
            return
        }
        super.touchesBegan(touches, with: event)
    }
    #endif

    func loadMarkdown(_ markdown: String) {
        session.loadMarkdown(markdown, into: documentTextStorage)
    }

    func setMode(_ mode: EditorMode) {
        session.setMode(mode, textStorage: documentTextStorage)
        onTextDidChange?()
        // `session.setMode` invalidates TextKit 2's own layout, but that
        // alone never schedules an AppKit/UIKit redraw of this view's
        // custom-drawn content (`draw(_:)` composes glyphs manually,
        // it isn't `NSTextView`) — without this, switching modes updated
        // `session.mode` and the SwiftUI picker's highlight (both driven
        // by `onTextDidChange`/`objectWillChange`) but the visible pixels
        // never changed, so Source appeared to do nothing.
        #if os(macOS)
        needsDisplay = true
        // Switching to Source is switching *into an editable state*, but
        // nothing was ever explicitly making this view first responder —
        // a user had to separately click inside the text area first, and
        // even then (see `mouseDown`) that click alone doesn't guarantee
        // real keyboard focus if something else already held it. Without
        // this, the caret drawn after switching modes was just
        // `caretVisible`'s static default (never blinking, never wired
        // to real `keyDown`/`insertText`), and typing went nowhere —
        // AppKit's default response to a key event nothing claims is a
        // beep. The `!== self` check just avoids a redundant reassignment
        // when this view already has focus.
        if mode == .source, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        #else
        setNeedsDisplay()
        #endif
    }

    func setTheme(_ tokens: ThemeTokens) {
        session.setTheme(tokens, textStorage: documentTextStorage)
        paintCanvasBackground()
    }

    func setZoomScale(_ scale: CGFloat) {
        session.setZoomScale(scale, textStorage: documentTextStorage)
        onTextDidChange?()
        // Same real-repaint gap as `setMode` above.
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    func foldCurrent() {
        let preferred = sourceLine(atY: lastJumpedPackedY ?? 0)
        if let preferred, foldableSourceLines().contains(preferred) {
            toggleFold(atSourceLine: preferred)
            return
        }
        if let first = foldableSourceLines().first {
            toggleFold(atSourceLine: first)
        }
    }

    func applyFolds() {
        session.applyFolds()
    }

    func foldAll() {
        session.foldAll(textStorage: documentTextStorage)
        ensureLayout()
        onTextDidChange?()
    }

    func unfoldAll() {
        session.unfoldAll(textStorage: documentTextStorage)
        ensureLayout()
        onTextDidChange?()
    }

    func ensureLayout() {
        updateTextContainerForGutter()
        session.ensureLayout()
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    private func updateTextContainerForGutter() {
        let width = max(40, bounds.width - gutterWidth)
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if textContainer.size != size {
            textContainer.size = size
            session.applyFolds()
        }
    }

    @discardableResult
    func handleGutterClick(at point: CGPoint) -> Bool {
        guard point.x >= 0, point.x <= gutterWidth else { return false }
        guard point.x <= GutterMetrics.chevronWidth else { return true }
        guard let clickedLine = sourceLine(atY: point.y) else { return true }
        // The clicked line is whatever the click's y genuinely resolves
        // to (always a real, visible line). A foldable block's own
        // anchor can itself be invisible (a fence's opening delimiter is
        // always markup-only, R10), so match against each foldable
        // block's *resolved display line*, not its raw start line — the
        // same resolution `drawGutter` uses to place the chevron there
        // in the first place, so whatever is drawn is exactly what's
        // clickable.
        let map = session.sourceLineMap()
        guard let block = blocks.first(where: { block in
            guard block.foldExtent != nil else { return false }
            return session.nearestVisibleLine(atOrAfter: block.id.startLine, in: map) == clickedLine
        }) else { return true }
        toggleFold(atSourceLine: block.id.startLine)
        return true
    }

    /// `visibleRect` bounds both the source-line scan (T02) and the
    /// foldable-line lookup to what is actually on screen — the gutter
    /// never needs off-screen entries, since nothing off-screen can be
    /// drawn or clicked. Source mode numbers every visible entry
    /// (unchanged); Preview numbers only each rendered block's true
    /// start (R13) — see `drawPreviewGutterNumbersAndChevrons`. Internal
    /// rather than `private` so tests can call the real per-frame draw
    /// path directly against a bitmap `CGContext` (mirroring
    /// `FoldingSession.drawFragments`, ticket 10's own precedent for
    /// testing a per-frame draw method's bounded cost).
    func drawGutter(in context: CGContext, visibleRect: CGRect) {
        let gutterRect = CGRect(x: 0, y: 0, width: gutterWidth, height: max(bounds.height, layoutHeight))
        context.saveGState()
        #if os(macOS)
        NSColor.controlBackgroundColor.withAlphaComponent(0.35).setFill()
        #else
        UIColor.secondarySystemBackground.withAlphaComponent(0.35).setFill()
        #endif
        context.fill(gutterRect)

        let map = session.sourceLineMap(boundedBy: visibleRect)
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.monospaced(size: 11),
            .foregroundColor: PlatformColor.secondaryLabel,
        ]

        if mode == .preview {
            drawPreviewGutterNumbersAndChevrons(in: context, map: map, numberAttrs: numberAttrs)
        } else {
            drawSourceGutterNumbersAndChevrons(in: context, map: map, numberAttrs: numberAttrs)
        }
        context.restoreGState()
    }

    /// Source mode: unchanged from before this ticket — a chevron and a
    /// number for every visible entry, one-to-one with source lines.
    private func drawSourceGutterNumbersAndChevrons(in context: CGContext, map: SourceLineMap, numberAttrs: [NSAttributedString.Key: Any]) {
        let visibleLines = Set(map.entries.map(\.sourceLine))
        let foldable = Set(blocks.compactMap { block -> Int? in
            guard block.foldExtent != nil, visibleLines.contains(block.id.startLine) else { return nil }
            return block.id.startLine
        })
        for entry in map.entries {
            if foldable.contains(entry.sourceLine) {
                drawChevron(in: context, at: chevronOrigin(for: entry), folded: isFolded(startLine: entry.sourceLine))
            }
            if showLineNumbers {
                drawNumber(entry.sourceLine, at: entry, attrs: numberAttrs, in: context)
            }
        }
    }

    /// Preview mode (R13): a chevron for every foldable block and a
    /// number for every rendered block's true start — each resolved to
    /// the nearest visible line at or after its own anchor, since a
    /// block's own start line is sometimes itself invisible markup. The
    /// *drawn* number is always the block's real anchor line; only
    /// *where* it draws can differ from that line's own (nonexistent)
    /// position.
    ///
    /// Resolution goes through `FoldingSession.resolveOntoVisibleMap`
    /// (a batch, binary-search-seeded pass over the already viewport-
    /// bounded `map`), not a `nearestVisibleLine` call per document-wide
    /// candidate — the latter is what a review on this ticket found
    /// reintroducing an O((blocks + anchors) × viewport) cost per draw,
    /// the same O(document × viewport) shape ticket 10 fixed for
    /// `packedSourceLineEntries` (P2). `blocks`/`previewBlockAnchorLinesSorted`
    /// are both already ascending by line (document order / pre-sorted
    /// at reparse), which `resolveOntoVisibleMap` requires.
    private func drawPreviewGutterNumbersAndChevrons(in context: CGContext, map: SourceLineMap, numberAttrs: [NSAttributedString.Key: Any]) {
        guard !map.entries.isEmpty else { return }
        session.resetGutterResolutionSteps()

        let foldableBlocks: [(line: Int, payload: Block)] = blocks.compactMap { block in
            guard block.foldExtent != nil else { return nil }
            return (line: block.id.startLine, payload: block)
        }
        for resolved in session.resolveOntoVisibleMap(foldableBlocks, in: map) {
            drawChevron(in: context, at: chevronOrigin(for: resolved.entry), folded: foldStore.isFolded(resolved.payload.id))
        }

        guard showLineNumbers else { return }
        for resolved in session.resolveOntoVisibleMap(session.previewBlockAnchorLinesSorted, in: map) {
            drawNumber(resolved.line, at: resolved.entry, attrs: numberAttrs, in: context)
        }
    }

    private func isFolded(startLine: Int) -> Bool {
        blocks.first(where: { $0.id.startLine == startLine }).map { foldStore.isFolded($0.id) } ?? false
    }

    private func chevronOrigin(for entry: SourceLineMap.Entry) -> CGPoint {
        CGPoint(x: 4, y: entry.y + max(2, (entry.height - 8) / 2))
    }

    private func drawNumber(_ number: Int, at entry: SourceLineMap.Entry, attrs: [NSAttributedString.Key: Any], in context: CGContext) {
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attrs)
        let x = GutterMetrics.chevronWidth + GutterMetrics.numberWidth - 6 - size.width
        let y = entry.y + max(0, (min(entry.height, size.height + 4) - size.height) / 2)
        label.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    private func drawChevron(in context: CGContext, at origin: CGPoint, folded: Bool) {
        let size: CGFloat = 8
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        if folded {
            context.move(to: CGPoint(x: 1, y: 0))
            context.addLine(to: CGPoint(x: size, y: size / 2))
            context.addLine(to: CGPoint(x: 1, y: size))
        } else {
            context.move(to: CGPoint(x: 0, y: 2))
            context.addLine(to: CGPoint(x: size, y: 2))
            context.addLine(to: CGPoint(x: size / 2, y: size))
        }
        context.closePath()
        context.setFillColor(PlatformColor.secondaryLabel.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private var hostWindow: AnyObject?

    #if os(macOS)
    /// Safety net for T01's blink timer: `prepareForEditing()` (test
    /// scaffolding predating this ticket, also used by
    /// `insertTextAtCaret`) creates a real `NSWindow`/`hostWindow` pair
    /// with `self` as `contentView` — a real, if usually test-scoped,
    /// strong reference cycle (view retains window via `hostWindow`,
    /// window retains view via `contentView`), and nothing before T01
    /// ever left anything actively running against it. T01's
    /// `becomeFirstResponder` override now schedules a genuinely
    /// repeating system `Timer`, which — if a caller never calls
    /// `resignFirstResponder()`/tears the window down — keeps firing
    /// indefinitely against a stale view for the rest of the process's
    /// life. Found via a real crash (not a hang): running the full
    /// `TextInputTests` suite intermittently crashed the shared AppKit
    /// test host (`EXC_BREAKPOINT` inside `FoldingTextView
    /// .__ivar_destroyer`, releasing the `hostWindow` ivar) once enough
    /// such leaked, still-ticking timers had accumulated across many
    /// `prepareForEditing()`-using tests. This `deinit` is the general
    /// backstop; call sites that create a real window should still
    /// prefer explicit teardown (`resignFirstResponder()`) where
    /// convenient, since a genuine reference cycle means `deinit` may
    /// never run without it.
    deinit {
        caretBlinkTimer?.invalidate()
        reparseDebounceTimer?.invalidate()
    }
    #endif

    func prepareForEditing() {
        #if os(macOS)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = self
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
        hostWindow = window
        #else
        let window = UIWindow(frame: frame)
        let host = UIViewController()
        host.view.frame = frame
        host.view.addSubview(self)
        window.rootViewController = host
        window.makeKeyAndVisible()
        becomeFirstResponder()
        hostWindow = window
        #endif
    }

    func insertTextAtCaret(_ string: String) {
        prepareForEditing()
        let nsString = string as NSString
        let insertRange = NSRange(location: 0, length: 0)
        documentTextStorage.replaceCharacters(in: insertRange, with: string)
        let inserted = NSRange(location: 0, length: nsString.length)
        // `registerUndo` requires an open group at call time — true
        // even pre-T03, but previously papered over by
        // `editingUndoManager`'s default `groupsByEvent = true`
        // supplying an implicit one automatically. T03 disables
        // `groupsByEvent` (see `completeInit`'s doc comment: the
        // automatic per-event group was nesting unpredictably inside
        // this view's own explicit coalescing groups), which turned
        // this pre-existing test helper's bare `registerUndo` call
        // into a real crash risk it never previously had. Same fix
        // shape as `unmarkText()`'s: an explicit, immediately-closed
        // group of its own.
        if editingUndoManager.groupingLevel > 0 {
            editingUndoManager.endUndoGrouping()
        }
        editingUndoManager.beginUndoGrouping()
        // T04: target `self`, not just `documentTextStorage`, so the
        // undo replay can also fire `onTextDidChange`/
        // `onTextChangeCommitted` — this test-only helper's own undo
        // previously left both silent, unlike every real T01-T03
        // mutation path (which already gets this via `mutateSourceText`).
        editingUndoManager.registerUndo(withTarget: self) { view in
            view.documentTextStorage.replaceCharacters(in: inserted, with: "")
            view.onTextDidChange?()
            view.onTextChangeCommitted?(view.currentTextChangeKind)
        }
        editingUndoManager.endUndoGrouping()
        onTextDidChange?()
        onTextChangeCommitted?(currentTextChangeKind)
    }

    /// T03: if a coalescing group (a run of contiguous single-character
    /// edits) is still open when undo is requested, close it first —
    /// `UndoManager.undo()` while `groupingLevel > 0` is a programming
    /// error (it asserts). A real coalescing streak otherwise only ever
    /// closes lazily, at the next edit that doesn't continue it; undo
    /// can arrive at any time, including mid-streak.
    func undoLastChange() -> Bool {
        if editingUndoManager.groupingLevel > 0 {
            editingUndoManager.endUndoGrouping()
        }
        guard editingUndoManager.canUndo else { return false }
        editingUndoManager.undo()
        return true
    }

    /// The redo counterpart of `undoLastChange()` (R20/R21 "undo and
    /// redo work"). No menu item routes to this today — R3 enumerates
    /// the Edit menu's required items (Find, Go to Line, Fold All,
    /// Unfold All) and Undo/Redo are not among them, so this is reached
    /// programmatically (tests; a future menu item, out of this
    /// ticket's scope) rather than via a `Selector`-based responder-chain
    /// action the way `undoLastChange` also isn't wired to Cmd+Z today.
    func redoLastChange() -> Bool {
        if editingUndoManager.groupingLevel > 0 {
            editingUndoManager.endUndoGrouping()
        }
        guard editingUndoManager.canRedo else { return false }
        editingUndoManager.redo()
        return true
    }
}

#if os(macOS)
extension FoldingTextView {
    // MARK: - T01: NSTextInputClient — caret geometry, blinking, IME/dictation

    private static let caretBlinkInterval: TimeInterval = 0.5

    private func startCaretBlinking() {
        caretVisible = true
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = Timer.scheduledTimer(withTimeInterval: Self.caretBlinkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.toggleCaretVisibility()
            }
        }
    }

    private func stopCaretBlinking() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        caretVisible = true
        needsDisplay = true
    }

    /// The exact toggle the blink timer calls each tick — exposed
    /// (rather than only reachable via a real timer firing) so tests can
    /// assert the toggle's own real effect directly and deterministically
    /// (N9), instead of sleeping for a wall-clock interval.
    func toggleCaretVisibility() {
        caretVisible.toggle()
        needsDisplay = true
    }

    // MARK: - T05: debounced reparse off the keystroke path

    /// Comfortably under the Bulk budget's 200 ms (Performance budgets
    /// table) so a keystroke burst's reparse still lands well inside
    /// it, while being long enough that ordinary typing cadence (real
    /// keystrokes tens of milliseconds apart) keeps rescheduling
    /// instead of firing mid-word.
    private static let reparseDebounceInterval: TimeInterval = 0.12

    /// Cancels any pending debounced reparse and schedules a new one —
    /// called from every keystroke-path mutation (`mutateSourceText`),
    /// never from `replaceSelection(with:)` (Find/Replace), which keeps
    /// reparsing synchronously per the plan (it is not a keystroke-path
    /// caller).
    private func scheduleDebouncedReparse() {
        reparseDebounceTimer?.invalidate()
        reparseDebounceTimer = Timer.scheduledTimer(withTimeInterval: Self.reparseDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fireDebouncedReparse()
            }
        }
    }

    /// The exact action the debounce timer performs when it fires —
    /// exposed (rather than only reachable via a real timer firing) so
    /// tests can assert its real effect directly and deterministically
    /// (N9), the same testability precedent as `toggleCaretVisibility`
    /// for the blink timer. `session.syncBlocksFromStorage()` is the
    /// existing "reparse + ticket 12's fold repair + restyle + full
    /// relayout" sequence (`FoldingSession.syncBlocksFromStorage`) —
    /// this only changes *when* it runs, not what it does.
    func fireDebouncedReparse() {
        reparseDebounceTimer?.invalidate()
        reparseDebounceTimer = nil
        session.syncBlocksFromStorage()
        needsDisplay = true
    }

    /// Whether a debounced reparse is currently pending — the live,
    /// testable proxy for "did the last keystroke schedule/reschedule
    /// the debounce" (N9), since a private `Timer` reference can't be
    /// asserted on directly.
    var hasPendingDebouncedReparse: Bool {
        reparseDebounceTimer != nil
    }

    /// Draws the blinking caret at `selectedUTF16Range`'s location when
    /// the selection is a real (zero-length) caret, in Source mode, and
    /// the current blink phase is on. Internal (not `private`) so tests
    /// can exercise the real per-frame draw path directly against a
    /// bitmap `CGContext`, mirroring `drawGutter`'s own testability
    /// precedent (ticket 10/09).
    func drawCaret(in context: CGContext) {
        guard session.mode == .source, selectedUTF16Range.length == 0, caretVisible else { return }
        guard let packedRect = session.packedCaretRect(forUTF16Offset: selectedUTF16Range.location, boundedBy: currentVisiblePackedRect()) else { return }
        let rect = CGRect(x: packedRect.minX + gutterWidth, y: packedRect.minY, width: max(packedRect.width, 1.5), height: packedRect.height)
        context.saveGState()
        context.setFillColor(PlatformColor.label.cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    /// The single primitive every keystroke-path mutation (`insertText`,
    /// backspace/delete, IME marked-text updates) routes through for the
    /// immediate buffer edit — the same "replace range, wrapped in
    /// begin/endEditing" shape as `FindReplace.replace`/
    /// `replaceSelection(with:)` (the ticket's Design note names this as
    /// the existing "mutate then reparse" precedent to reuse). The
    /// buffer mutation and glyph display happen synchronously, same-
    /// frame (R20's "typing inserts at the caret") — real TextKit 2
    /// incremental layout already relays out the edited range as soon
    /// as `documentTextStorage` changes, independent of this method.
    /// Only `session.syncBlocksFromStorage()` (reparse + ticket 12's
    /// fold repair + restyle + full relayout) is debounced (T05): a
    /// keystroke burst reparses once, after a quiet period, not once
    /// per character — see `scheduleDebouncedReparse`. Mode gating
    /// (`session.mode == .source`) happens at each public entry point, not here, so that
    /// undo/redo — which must keep working even if the user has since
    /// switched to Preview — is never itself blocked by the gate that
    /// stops *new* edits.
    /// `undoPreviousOverride`, when supplied, is registered as the
    /// undo step's inverse text instead of `range`'s actual current
    /// contents — needed for committing a marked-text (IME/dictation)
    /// composition (`insertText` while `hasMarkedText()`, or
    /// `unmarkText()`): the range being "replaced" at commit time
    /// already holds the *composed* text (`setMarkedText` writes each
    /// revision straight into the buffer, per its own doc comment), so
    /// naively capturing "whatever's there now" as the undo inverse
    /// would just replace the composed text with itself — a no-op that
    /// silently drops the whole composition session from the undo
    /// stack. The override carries the true pre-composition text
    /// forward instead, so the commit's one undo step restores exactly
    /// what was there before composition began.
    /// `coalescingKind`, when non-nil and `registerUndo` is true (T03),
    /// makes this a candidate to join the same open `editingUndoManager`
    /// group as the previous coalescable edit — see
    /// `applyCoalescingGrouping`. Left `nil` (the default) for anything
    /// that must never coalesce: a multi-character insert/paste, an IME
    /// commit, a selection-replacing edit, or — critically — the
    /// self-registered undo-inverse closure below, which always omits
    /// it so an undo/redo replay is never itself treated as a fresh
    /// coalescable edit.
    @discardableResult
    private func mutateSourceText(
        in range: NSRange,
        with replacement: String,
        registerUndo: Bool = true,
        undoPreviousOverride: String? = nil,
        coalescingKind: CoalescingKind? = nil
    ) -> Bool {
        guard range.location != NSNotFound, NSMaxRange(range) <= documentTextStorage.length else { return false }
        // Never manage grouping while an undo/redo replay is actually
        // in progress: `UndoManager.undo()`/`.redo()` already opens its
        // own internal group around the replay so the inverse actions
        // it invokes register as one atomic redo/undo step — calling
        // `endUndoGrouping()` from inside that (which `groupingLevel >
        // 0` would otherwise trigger, since the manager's own internal
        // group counts too) would prematurely close the replay's own
        // group and corrupt the undo manager's bookkeeping.
        let isReplaying = editingUndoManager.isUndoing || editingUndoManager.isRedoing
        if registerUndo, !isReplaying {
            applyCoalescingGrouping(for: coalescingKind, range: range)
        }
        let previous = undoPreviousOverride ?? (documentTextStorage.string as NSString).substring(with: range)
        let ok = FindReplace.replace(range, with: replacement, in: documentTextStorage)
        guard ok else { return false }
        let insertedLength = (replacement as NSString).length
        let insertedRange = NSRange(location: range.location, length: insertedLength)
        if registerUndo {
            editingUndoManager.registerUndo(withTarget: self) { view in
                view.mutateSourceText(in: insertedRange, with: previous)
            }
        }
        selectedUTF16Range = NSRange(location: range.location + insertedLength, length: 0)
        selectionAnchorOffset = nil
        if registerUndo {
            self.coalescingKind = coalescingKind
            coalescingCaretOffset = coalescingKind != nil ? selectedUTF16Range.location : nil
            coalescingLastEditAt = coalescingClock()
        }
        scheduleDebouncedReparse()
        onTextDidChange?()
        onTextChangeCommitted?(currentTextChangeKind)
        needsDisplay = true
        return true
    }

    /// Opens, continues, or closes `editingUndoManager`'s undo group so
    /// a contiguous run of same-kind single-character edits arriving
    /// within `coalescingWindow` of each other becomes ONE undo step
    /// (T03) — "typing 'hello' should be one undo step, not five." A
    /// non-contiguous edit (caret moved elsewhere, then typed), a
    /// different kind (an insert run doesn't merge with a delete run),
    /// a stale streak (paused too long), or any non-coalescable edit
    /// (`kind == nil`: a paste/multi-char insert, an IME commit,
    /// replacing a selection, an undo/redo replay) always starts fresh.
    /// Nested `beginUndoGrouping()`/`endUndoGrouping()` calls are what
    /// actually coalesce multiple `registerUndo` calls into one
    /// `undo()` step — NSUndoManager's own per-"event" auto-grouping
    /// isn't reliable here (headless tests and real keystrokes don't
    /// share a run-loop-cycle boundary the same way), so this manages
    /// the group explicitly rather than depending on it.
    private static let coalescingWindow: TimeInterval = 2.0

    private func applyCoalescingGrouping(for kind: CoalescingKind?, range: NSRange) {
        var continuesStreak = false
        if let kind, let previousKind = coalescingKind, kind == previousKind,
           let lastCaret = coalescingCaretOffset,
           coalescingClock().timeIntervalSince(coalescingLastEditAt) <= Self.coalescingWindow {
            switch kind {
            case .insert:
                continuesStreak = range.location == lastCaret
            case .deleteBackward:
                continuesStreak = range.upperBound == lastCaret
            case .deleteForward:
                continuesStreak = range.location == lastCaret
            }
        }

        if continuesStreak { return }

        // Every call that is about to `registerUndo` needs *some* open
        // group at that moment — `UndoManager.registerUndo` throws
        // ("must begin a group before registering undo") without one,
        // and nothing here can rely on NSUndoManager's own per-"event"
        // auto-grouping to supply it (see this method's doc comment).
        // A non-coalescable edit (`kind == nil`) still needs its own
        // self-contained group; it just won't be treated as
        // continuable by the *next* edit (`coalescingKind` is reset to
        // `nil` alongside it in `mutateSourceText`), so the next call
        // always finds `continuesStreak == false` and closes this group
        // before opening its own — found via a real crash (not
        // guessed): a genuine `NSInternalInconsistencyException`
        // ("must begin a group before registering undo") on the very
        // first multi-character `insertText` call, once a serial (non-
        // parallel) test run separated it from unrelated flaky
        // SwiftUI/AppKit contention noise that had been masking it.
        if editingUndoManager.groupingLevel > 0 {
            editingUndoManager.endUndoGrouping()
        }
        editingUndoManager.beginUndoGrouping()
    }

    private func deleteBackward() {
        if selectedUTF16Range.length > 0 {
            mutateSourceText(in: selectedUTF16Range, with: "")
            return
        }
        guard selectedUTF16Range.location > 0 else { return }
        let range = NSRange(location: selectedUTF16Range.location - 1, length: 1)
        mutateSourceText(in: range, with: "", coalescingKind: .deleteBackward)
    }

    private func deleteForward() {
        if selectedUTF16Range.length > 0 {
            mutateSourceText(in: selectedUTF16Range, with: "")
            return
        }
        guard selectedUTF16Range.location < documentTextStorage.length else { return }
        let range = NSRange(location: selectedUTF16Range.location, length: 1)
        mutateSourceText(in: range, with: "", coalescingKind: .deleteForward)
    }

    // MARK: - T02: selection drawing, mouse click/drag, keyboard navigation, copy

    /// Draws the selection highlight (skip hidden ranges the same way
    /// `drawFragments`/`drawCaret` already do — via `session
    /// .packedSelectionRects`, which only ever walks non-collapsed
    /// fragments). Internal so tests can exercise the real per-frame
    /// draw path directly against a bitmap `CGContext`, mirroring
    /// `drawGutter`/`drawCaret`'s own testability precedent.
    func drawSelectionHighlight(in context: CGContext, visibleRect: CGRect) {
        // T06: Preview is selectable too (R22) — the geometry is drawn
        // from whatever's actually laid out (rendered glyph positions),
        // correct in either mode without further change.
        guard selectedUTF16Range.length > 0 else { return }
        let rects = session.packedSelectionRects(forUTF16Range: selectedUTF16Range, boundedBy: visibleRect)
        guard !rects.isEmpty else { return }
        context.saveGState()
        PlatformColor.selectionHighlight.setFill()
        for rect in rects {
            context.fill(rect)
        }
        context.restoreGState()
    }

    /// `viewPoint` is in this view's own (window-converted) coordinate
    /// system, gutter included — subtracts `gutterWidth` before handing
    /// off to `session.utf16Offset(atPackedPoint:boundedBy:)` (T01),
    /// bounded to the current viewport (P1) since click/drag is a
    /// continuous, per-frame interaction.
    private func utf16Offset(forViewPoint viewPoint: CGPoint) -> Int? {
        let packedPoint = CGPoint(x: viewPoint.x - gutterWidth, y: viewPoint.y)
        return session.utf16Offset(atPackedPoint: packedPoint, boundedBy: currentVisiblePackedRect())
    }

    private func clampedOffset(_ offset: Int) -> Int {
        max(0, min(offset, documentTextStorage.length))
    }

    private func normalizedRange(_ a: Int, _ b: Int) -> NSRange {
        let lower = clampedOffset(min(a, b))
        let upper = clampedOffset(max(a, b))
        return NSRange(location: lower, length: upper - lower)
    }

    /// The word (contiguous alphanumeric/underscore run) containing
    /// `offset`, or — when `offset` lands on whitespace/punctuation —
    /// the contiguous run of that same character, matching standard
    /// double-click word-selection behavior for non-word characters.
    private func wordRange(at offset: Int) -> NSRange {
        let ns = documentTextStorage.string as NSString
        let length = ns.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        func isWordChar(_ i: Int) -> Bool {
            guard i >= 0, i < length else { return false }
            guard let scalar = Unicode.Scalar(ns.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        var start = min(offset, length - 1)
        var end = min(offset, length - 1)
        if !isWordChar(start) {
            let boundaryChar = ns.character(at: start)
            while end + 1 < length, !isWordChar(end + 1), ns.character(at: end + 1) == boundaryChar { end += 1 }
            while start - 1 >= 0, !isWordChar(start - 1), ns.character(at: start - 1) == boundaryChar { start -= 1 }
            return NSRange(location: start, length: end - start + 1)
        }
        while start > 0, isWordChar(start - 1) { start -= 1 }
        while end + 1 < length, isWordChar(end + 1) { end += 1 }
        return NSRange(location: start, length: end - start + 1)
    }

    /// The source line boundaries around `offset`, excluding the
    /// terminating newline — shared by triple-click line selection
    /// (which re-adds the newline separately) and Cmd+Left/Right line-
    /// boundary keyboard navigation (which must not skip past it).
    private func lineRangeExcludingNewline(at offset: Int) -> NSRange {
        let ns = documentTextStorage.string as NSString
        let length = ns.length
        var start = min(max(0, offset), length)
        while start > 0, ns.character(at: start - 1) != 0x0A { start -= 1 }
        var end = min(max(0, offset), length)
        while end < length, ns.character(at: end) != 0x0A { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Triple-click's unit: the line including its trailing newline (if
    /// any), matching standard "select whole line" behavior.
    private func lineRange(at offset: Int) -> NSRange {
        let bare = lineRangeExcludingNewline(at: offset)
        let length = documentTextStorage.length
        let end = bare.upperBound < length ? bare.upperBound + 1 : bare.upperBound
        return NSRange(location: bare.location, length: end - bare.location)
    }

    /// A word-boundary offset from `offset`, scanning `forward` or
    /// backward — Option+Left/Right's "reasonable minimum" per the
    /// plan (not a full Unicode word-break algorithm).
    private func wordBoundaryOffset(from offset: Int, forward: Bool) -> Int {
        let ns = documentTextStorage.string as NSString
        let length = ns.length
        func isWordChar(_ i: Int) -> Bool {
            guard i >= 0, i < length else { return false }
            guard let scalar = Unicode.Scalar(ns.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        var index = clampedOffset(offset)
        if forward {
            while index < length, !isWordChar(index) { index += 1 }
            while index < length, isWordChar(index) { index += 1 }
        } else {
            while index > 0, !isWordChar(index - 1) { index -= 1 }
            while index > 0, isWordChar(index - 1) { index -= 1 }
        }
        return index
    }

    /// The offset a caret-movement command should start from: the
    /// existing extension's moving end when one is already in progress;
    /// otherwise, for a plain (non-extending) move with an active
    /// selection, the boundary in the direction of travel (standard
    /// "arrow key collapses selection to that edge" behavior); otherwise
    /// the current collapsed caret.
    private func currentMovingOffset(forward: Bool, extend: Bool) -> Int {
        if extend, let anchor = selectionAnchorOffset {
            return selectedUTF16Range.location == anchor ? selectedUTF16Range.upperBound : selectedUTF16Range.location
        }
        if !extend, selectedUTF16Range.length > 0 {
            return forward ? selectedUTF16Range.upperBound : selectedUTF16Range.location
        }
        return forward ? selectedUTF16Range.upperBound : selectedUTF16Range.location
    }

    /// Commits a caret-movement command's result: collapses to
    /// `newOffset` when not extending (clearing any tracked anchor),
    /// otherwise grows/shrinks the selection between the tracked (or
    /// newly-established) anchor and `newOffset`.
    private func applyCaretMove(to newOffset: Int, extend: Bool, directionForward: Bool) {
        let clamped = clampedOffset(newOffset)
        if extend {
            let anchor = selectionAnchorOffset ?? (directionForward ? selectedUTF16Range.location : selectedUTF16Range.upperBound)
            selectionAnchorOffset = anchor
            selectedUTF16Range = normalizedRange(anchor, clamped)
        } else {
            selectionAnchorOffset = nil
            selectedUTF16Range = NSRange(location: clamped, length: 0)
        }
        needsDisplay = true
    }

    /// Review fix: previously did raw `movingFrom + delta` arithmetic
    /// with no awareness of hidden/folded ranges, unlike click/drag
    /// placement and vertical movement (both point-based, and both
    /// already fold-aware via `enumeratePackedVisibleFragments`).
    /// Arrowing across a fold's boundary landed the caret inside the
    /// hidden byte range, where `packedCaretRect` returns `nil` and the
    /// caret silently stopped drawing — contradicting both the design
    /// note and T02's own plan text ("arrow keys move the caret (skip
    /// hidden ranges)"). Every computed target now passes through
    /// `session.skipHiddenUTF16Offset`, which jumps straight past a
    /// hidden range to its far edge in the direction of travel — the
    /// same "one press skips the whole hidden span" behavior the point-
    /// based paths already have.
    private func moveHorizontally(by delta: Int, extend: Bool) {
        let forward = delta > 0
        if !extend, selectedUTF16Range.length > 0 {
            // First press of a plain arrow key with an active selection:
            // collapse to the edge in the direction of travel — no
            // additional step on top of that, matching standard "arrow
            // key collapses the selection" behavior (a second press,
            // now from a collapsed caret, steps by one as usual).
            let edge = forward ? selectedUTF16Range.upperBound : selectedUTF16Range.location
            applyCaretMove(to: session.skipHiddenUTF16Offset(edge, movingForward: forward), extend: false, directionForward: forward)
            return
        }
        let movingFrom = currentMovingOffset(forward: forward, extend: extend)
        let stepped = clampedOffset(movingFrom + delta)
        let visible = session.skipHiddenUTF16Offset(stepped, movingForward: forward)
        applyCaretMove(to: visible, extend: extend, directionForward: forward)
    }

    /// Moves the caret/selection-extending-end up or down one line by
    /// resolving the current caret's own x-position at a y one line
    /// height above/below it — the standard "keep column, change line"
    /// approach — via the same point↔offset helpers mouse click/drag
    /// use. Bounded by the current viewport (P1): holding an arrow key
    /// repeats at a continuous, per-frame rate.
    private func moveVertically(by lineDelta: Int, extend: Bool) {
        let movingFrom = currentMovingOffset(forward: lineDelta > 0, extend: extend)
        guard let rect = session.packedCaretRect(forUTF16Offset: movingFrom, boundedBy: currentVisiblePackedRect()) else { return }
        let targetY = rect.midY + CGFloat(lineDelta) * max(rect.height, 1)
        let point = CGPoint(x: rect.minX, y: targetY)
        guard let newOffset = session.utf16Offset(atPackedPoint: point, boundedBy: currentVisiblePackedRect()) else { return }
        applyCaretMove(to: newOffset, extend: extend, directionForward: lineDelta > 0)
    }

    private func moveToWordBoundary(forward: Bool, extend: Bool) {
        let movingFrom = currentMovingOffset(forward: forward, extend: extend)
        let newOffset = wordBoundaryOffset(from: movingFrom, forward: forward)
        applyCaretMove(to: newOffset, extend: extend, directionForward: forward)
    }

    private func moveToLineBoundary(forward: Bool, extend: Bool) {
        let movingFrom = currentMovingOffset(forward: forward, extend: extend)
        let range = lineRangeExcludingNewline(at: movingFrom)
        let newOffset = forward ? range.upperBound : range.location
        applyCaretMove(to: newOffset, extend: extend, directionForward: forward)
    }

    /// Source-mode copy (R20/R22): the buffer *is* the display in
    /// Source mode, so this is a trivial slice onto the pasteboard —
    /// Preview-mode copy (source-Markdown-from-rendered-selection) is
    /// T06's separate, harder problem.
    @objc func copy(_ sender: Any?) {
        let text: String?
        switch session.mode {
        case .source:
            text = selectedUTF16Range.length > 0
                ? (documentTextStorage.string as NSString).substring(with: selectedUTF16Range)
                : nil
        case .preview:
            // T06: Preview's own reverse mapping — block-line-grained
            // source Markdown, not a slice of the rendered/substituted
            // text (R22: "copying yields source Markdown"). Gated on a
            // real (non-empty) selection the same way Source mode is —
            // a bare caret position touching a block's own span (this
            // is deliberately true in `previewSelectionSourceLineRanges`
            // for a zero-length selection sitting right at a block's
            // start, matching how a caret is considered "on" the text
            // it precedes) must not make copy fire with nothing actually
            // selected.
            text = selectedUTF16Range.length > 0
                ? session.previewSelectionSourceMarkdown(forUTF16Range: selectedUTF16Range)
                : nil
        }
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - T07: accessibility

/// `FoldingTextView` is a bare `NSView`, not an `NSTextView` — it has
/// none of `NSTextView`'s built-in `NSAccessibility` conformance, so
/// VoiceOver would otherwise see an opaque, unreadable view. These
/// overrides give it the minimum a real text field needs: a
/// recognizable role, its text content, the current selection, and how
/// many characters it holds. `accessibilityValue` reports the raw
/// buffer in both modes (the single authoritative source, N4) rather
/// than attempting a separate accessible rendering of Preview's
/// substituted text — building a parallel "what a screen reader should
/// say for rendered Markdown" representation is real, separate scope
/// this ticket's plan does not ask for.
extension FoldingTextView {
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }

    /// Review fix: previously returned the raw buffer unconditionally
    /// in both modes, so VoiceOver in Preview would read literal syntax
    /// (`##`, `**bold**`, table pipes) instead of the rendered content
    /// Preview visually shows. Reuses ticket 08's own substitution
    /// index (`PreviewSubstitutionIndex.anchorSubstitutions`, keyed by
    /// each rendered block's document UTF-16 anchor offset) rather than
    /// building a second, parallel "how do I read this Markdown aloud"
    /// representation — sorting those substitutions into document order
    /// and joining their already-rendered strings gives real reading-
    /// view text with no new rendering machinery. Falls back to the raw
    /// buffer whenever there's no live substitution index (Source mode,
    /// or Preview mode before the first `applyStyling` call).
    override func accessibilityValue() -> Any? {
        guard session.mode == .preview, let index = session.contentStorageDelegate.index else {
            return documentTextStorage.string
        }
        return index.anchorSubstitutions
            .sorted { $0.key < $1.key }
            .map(\.value.string)
            .joined(separator: "\n")
    }

    override func accessibilitySelectedText() -> String? {
        guard selectedUTF16Range.length > 0,
              NSMaxRange(selectedUTF16Range) <= documentTextStorage.length
        else { return "" }
        return (documentTextStorage.string as NSString).substring(with: selectedUTF16Range)
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        selectedUTF16Range
    }

    /// The full document range — this view has no separate "visible
    /// viewport in UTF-16 terms" API today (the gutter/scroll machinery
    /// works in packed *y* coordinates, not character offsets), so this
    /// reports everything rather than a genuinely viewport-bounded
    /// slice. Still a correct, honest answer (VoiceOver treats it as
    /// "all of this text is available"), not a placeholder constant.
    override func accessibilityVisibleCharacterRange() -> NSRange {
        NSRange(location: 0, length: documentTextStorage.length)
    }

    override func accessibilityNumberOfCharacters() -> Int {
        documentTextStorage.length
    }
}

extension FoldingTextView: NSTextInputClient {
    /// Real text input, gated to Source mode (R20's "editing decision" —
    /// Preview stays read-only, R22). Replaces `replacementRange` when
    /// the input system supplies one, otherwise any active marked
    /// (composing) range, otherwise the current selection — the standard
    /// `NSTextInputClient` precedence. Committing while marked text is
    /// active clears it (`markedTextUTF16Range = nil`) — the composing
    /// text this replaces was never itself undo-registered (see
    /// `setMarkedText`), so this one call's undo step is the whole
    /// composition session's net effect, not just its last keystroke.
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard session.mode == .source else { return }
        let text: String
        if let string = string as? String {
            text = string
        } else if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else {
            return
        }
        let range: NSRange
        let undoOverride: String?
        if replacementRange.location != NSNotFound {
            range = replacementRange
            undoOverride = nil
        } else if let marked = markedTextUTF16Range {
            range = marked
            undoOverride = composingOriginalText
        } else {
            range = selectedUTF16Range
            undoOverride = nil
        }
        markedTextUTF16Range = nil
        composingOriginalText = nil
        // T03: only a genuine single-character insert into an empty
        // (non-replacing) range is coalescing-eligible — a multi-
        // character paste/IME commit, or replacing an existing
        // selection, always stands as its own undo step.
        let kind: CoalescingKind? = (range.length == 0 && (text as NSString).length == 1) ? .insert : nil
        mutateSourceText(in: range, with: text, undoPreviousOverride: undoOverride, coalescingKind: kind)
    }

    /// Keyboard commands `interpretKeyEvents(_:)` routes here when no
    /// marked text intercepts them first. T01 wires the minimum needed
    /// alongside `insertText` for basic editing to work at all
    /// (newline, backspace, forward-delete) — the Design note lists
    /// backspace/delete as one of the mutation paths that must share
    /// `insertText`'s mutate primitive, alongside it rather than as a
    /// separately numbered task. Arrow-key/word-boundary caret movement
    /// and shift-extended selection are T02's explicit "keyboard
    /// navigation" scope, not this method's.
    override func doCommand(by selector: Selector) {
        guard session.mode == .source else { return }
        switch selector {
        case Selector(("insertNewline:")), Selector(("insertNewlineIgnoringFieldEditor:")):
            mutateSourceText(in: selectedUTF16Range, with: "\n", coalescingKind: selectedUTF16Range.length == 0 ? .insert : nil)
        case Selector(("insertTab:")):
            mutateSourceText(in: selectedUTF16Range, with: "\t", coalescingKind: selectedUTF16Range.length == 0 ? .insert : nil)
        case Selector(("deleteBackward:")):
            deleteBackward()
        case Selector(("deleteForward:")):
            deleteForward()
        // T02: keyboard navigation — arrow keys move the caret (skip
        // hidden ranges, via the same point↔offset helpers mouse
        // click/drag use), Shift+arrow extends the selection,
        // Option+arrow/Cmd+arrow give word- and line-boundary movement
        // as the plan's explicit "reasonable minimum."
        case Selector(("moveLeft:")):
            moveHorizontally(by: -1, extend: false)
        case Selector(("moveRight:")):
            moveHorizontally(by: 1, extend: false)
        case Selector(("moveLeftAndModifySelection:")):
            moveHorizontally(by: -1, extend: true)
        case Selector(("moveRightAndModifySelection:")):
            moveHorizontally(by: 1, extend: true)
        case Selector(("moveUp:")):
            moveVertically(by: -1, extend: false)
        case Selector(("moveDown:")):
            moveVertically(by: 1, extend: false)
        case Selector(("moveUpAndModifySelection:")):
            moveVertically(by: -1, extend: true)
        case Selector(("moveDownAndModifySelection:")):
            moveVertically(by: 1, extend: true)
        case Selector(("moveWordLeft:")):
            moveToWordBoundary(forward: false, extend: false)
        case Selector(("moveWordRight:")):
            moveToWordBoundary(forward: true, extend: false)
        case Selector(("moveWordLeftAndModifySelection:")):
            moveToWordBoundary(forward: false, extend: true)
        case Selector(("moveWordRightAndModifySelection:")):
            moveToWordBoundary(forward: true, extend: true)
        case Selector(("moveToBeginningOfLine:")):
            moveToLineBoundary(forward: false, extend: false)
        case Selector(("moveToEndOfLine:")):
            moveToLineBoundary(forward: true, extend: false)
        case Selector(("moveToBeginningOfLineAndModifySelection:")):
            moveToLineBoundary(forward: false, extend: true)
        case Selector(("moveToEndOfLineAndModifySelection:")):
            moveToLineBoundary(forward: true, extend: true)
        default:
            break
        }
    }

    /// Real IME/dictation composing support, not a stub: the composing
    /// text is inserted into the buffer immediately (it is genuinely
    /// what a reader would see mid-composition — there is only ever one
    /// authoritative buffer, N4) each time the input system revises it,
    /// replacing whatever the previous marked range covered. Deliberately
    /// *not* undo-registered per intermediate revision (`registerUndo:
    /// false`) — composing "n" → "ni" → "nǐ" → "你" as four separate undo
    /// steps would be a confusing, meaningless undo stack; `insertText`'s
    /// eventual commit is the one undoable step for the whole session.
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard session.mode == .source else { return }
        let text: String
        if let string = string as? String {
            text = string
        } else if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else {
            text = ""
        }

        let replaceRange: NSRange
        if replacementRange.location != NSNotFound {
            replaceRange = replacementRange
        } else if let existing = markedTextUTF16Range {
            replaceRange = existing
        } else {
            replaceRange = selectedUTF16Range
        }

        if markedTextUTF16Range == nil {
            // Starting a new composing session: capture what
            // composition is about to replace, so the eventual commit's
            // one undo step (`insertText`/`unmarkText`) can restore
            // exactly this — not "whatever's in the buffer at commit
            // time," which by then is itself the already-composed text
            // (see `mutateSourceText`'s `undoPreviousOverride` doc).
            composingOriginalText = (documentTextStorage.string as NSString).substring(with: replaceRange)
        }

        guard mutateSourceText(in: replaceRange, with: text, registerUndo: false) else { return }
        let insertedLength = (text as NSString).length
        if insertedLength == 0 {
            markedTextUTF16Range = nil
            composingOriginalText = nil
            return
        }
        markedTextUTF16Range = NSRange(location: replaceRange.location, length: insertedLength)
        let clampedLocation = max(0, min(selectedRange.location, insertedLength))
        let clampedLength = max(0, min(selectedRange.length, insertedLength - clampedLocation))
        selectedUTF16Range = NSRange(location: replaceRange.location + clampedLocation, length: clampedLength)
    }

    /// Finalizes whatever marked text is currently in the buffer as-is
    /// (the characters stay; only the "still composing" marking clears)
    /// — the standard `NSTextInputClient.unmarkText()` contract. Unlike
    /// each individual `setMarkedText` revision, this settling is
    /// registered as one undo step (the composition's pre-session text
    /// as the inverse) — the input system can finalize a composition
    /// this way instead of always routing through `insertText`, and
    /// without this the whole session would otherwise leave no undo
    /// history at all.
    func unmarkText() {
        // Review fix (Minor): consistency with every other
        // NSTextInputClient entry point, all of which explicitly gate
        // on Source mode — this was the one exception, reachable only
        // if the user switches to Preview mid-composition.
        if session.mode == .source, let marked = markedTextUTF16Range, let original = composingOriginalText {
            // `registerUndo` requires *some* open group at the moment
            // it's called — `groupsByEvent` is disabled (T03's own
            // fix, see `completeInit`'s doc comment), so there is no
            // automatic fallback here the way there might otherwise be.
            // This path bypasses `mutateSourceText`/
            // `applyCoalescingGrouping` entirely (finalizing a
            // composition without an explicit `insertText` commit is
            // its own standalone action, never coalescable with
            // anything), so it must open and close its own group —
            // found via a real crash (`NSInternalInconsistencyException`
            // "must begin a group before registering undo"), the same
            // hazard class `applyCoalescingGrouping` already guards
            // against for every path that *does* go through
            // `mutateSourceText`.
            if editingUndoManager.groupingLevel > 0 {
                editingUndoManager.endUndoGrouping()
            }
            editingUndoManager.beginUndoGrouping()
            editingUndoManager.registerUndo(withTarget: self) { view in
                view.mutateSourceText(in: marked, with: original)
            }
            editingUndoManager.endUndoGrouping()
        }
        markedTextUTF16Range = nil
        composingOriginalText = nil
    }

    func markedRange() -> NSRange {
        markedTextUTF16Range ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedTextUTF16Range != nil
    }

    func selectedRange() -> NSRange {
        selectedUTF16Range
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= documentTextStorage.length else { return nil }
        actualRange?.pointee = range
        return documentTextStorage.attributedSubstring(from: range)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle]
    }

    /// Screen-coordinate rect for `range`'s first character — computed
    /// from `session.packedCaretRect`, then carried view → window →
    /// screen. Used by the input system to position IME composition
    /// candidate windows near the caret.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        guard let packedRect = session.packedCaretRect(forUTF16Offset: range.location, boundedBy: currentVisiblePackedRect()) else {
            let fallback = window?.frame ?? .zero
            return NSRect(x: fallback.minX, y: fallback.minY, width: 0, height: 0)
        }
        let viewRect = CGRect(
            x: packedRect.minX + gutterWidth,
            y: packedRect.minY,
            width: max(packedRect.width, 1),
            height: packedRect.height
        )
        let windowRect = convert(viewRect, to: nil)
        guard let window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    /// The inverse of `firstRect(forCharacterRange:actualRange:)`:
    /// screen point → document UTF-16 offset, via `session
    /// .utf16Offset(atPackedPoint:boundedBy:)` (T01) — the same point↔
    /// offset helper mouse click/drag selection (T02) uses.
    func characterIndex(for point: NSPoint) -> Int {
        let windowPoint = window?.convertPoint(fromScreen: point) ?? point
        let viewPoint = convert(windowPoint, from: nil)
        let packedPoint = CGPoint(x: viewPoint.x - gutterWidth, y: viewPoint.y)
        return session.utf16Offset(atPackedPoint: packedPoint, boundedBy: currentVisiblePackedRect()) ?? 0
    }
}
#endif

#if os(macOS)
struct FoldingTextViewRepresentable: NSViewRepresentable {
    var markdown: String
    var foldStore: FoldStore

    func makeNSView(context: Context) -> FoldingTextView {
        let view = FoldingTextView(foldStore: foldStore)
        view.loadMarkdown(markdown)
        return view
    }

    func updateNSView(_ nsView: FoldingTextView, context: Context) {}
}
#else
struct FoldingTextViewRepresentable: UIViewRepresentable {
    var markdown: String
    var foldStore: FoldStore

    func makeUIView(context: Context) -> FoldingTextView {
        let view = FoldingTextView(foldStore: foldStore)
        view.loadMarkdown(markdown)
        return view
    }

    func updateUIView(_ uiView: FoldingTextView, context: Context) {}
}
#endif

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

    private var documentString: String? {
        let string = textStorage?.string
            ?? contentStorage?.textStorage?.string
            ?? (layoutManager?.textContentManager as? NSTextContentStorage)?.textStorage?.string
        guard let string, !string.isEmpty else { return nil }
        return string
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

@MainActor
final class FoldingTextView: PlatformView {
    let session: FoldingSession
    let contentStorage: NSTextContentStorage
    let textLayoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer
    let documentTextStorage: NSTextStorage
    private let editingUndoManager = UndoManager()

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
        session.drawFragments(in: context, visibleRect: dirtyRect)
        context.restoreGState()
    }

    override func layout() {
        super.layout()
        updateTextContainerForGutter()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleGutterClick(at: point) { return }
        super.mouseDown(with: event)
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
    }

    func setTheme(_ tokens: ThemeTokens) {
        session.setTheme(tokens, textStorage: documentTextStorage)
        paintCanvasBackground()
    }

    func setZoomScale(_ scale: CGFloat) {
        session.setZoomScale(scale, textStorage: documentTextStorage)
        onTextDidChange?()
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
    /// start (R13) — see `drawPreviewGutterNumbersAndChevrons`.
    private func drawGutter(in context: CGContext, visibleRect: CGRect) {
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
    /// number for every rendered block's true start — each resolved,
    /// independently, to the nearest visible line at or after its own
    /// anchor (`FoldingSession.nearestVisibleLine`), since a block's own
    /// start line is sometimes itself invisible markup. The *drawn*
    /// number is always the block's real anchor line; only *where* it
    /// draws can differ from that line's own (nonexistent) position.
    private func drawPreviewGutterNumbersAndChevrons(in context: CGContext, map: SourceLineMap, numberAttrs: [NSAttributedString.Key: Any]) {
        guard !map.entries.isEmpty else { return }

        for block in blocks where block.foldExtent != nil {
            guard let displayLine = session.nearestVisibleLine(atOrAfter: block.id.startLine, in: map),
                  let entry = map.entries.first(where: { $0.sourceLine == displayLine })
            else { continue }
            drawChevron(in: context, at: chevronOrigin(for: entry), folded: foldStore.isFolded(block.id))
        }

        guard showLineNumbers else { return }
        for anchorLine in session.previewBlockAnchorLines.sorted() {
            guard let displayLine = session.nearestVisibleLine(atOrAfter: anchorLine, in: map),
                  let entry = map.entries.first(where: { $0.sourceLine == displayLine })
            else { continue }
            drawNumber(anchorLine, at: entry, attrs: numberAttrs, in: context)
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
        editingUndoManager.registerUndo(withTarget: documentTextStorage) { storage in
            storage.replaceCharacters(in: inserted, with: "")
        }
        onTextDidChange?()
    }

    func undoLastChange() -> Bool {
        guard editingUndoManager.canUndo else { return false }
        editingUndoManager.undo()
        return true
    }
}

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

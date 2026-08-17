import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#else
import UIKit
import SwiftUI
#endif

enum UTF8NSRange {
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
    private weak var layoutManager: NSTextLayoutManager?
    private weak var contentStorage: NSTextContentStorage?
    private weak var textStorage: NSTextStorage?

    init(foldStore: FoldStore = FoldStore(), mode: EditorMode = .preview, tokens: ThemeTokens = .default) {
        self.foldStore = foldStore
        self.mode = mode
        self.tokens = tokens
    }

    func attach(layoutManager: NSTextLayoutManager, contentStorage: NSTextContentStorage) {
        self.layoutManager = layoutManager
        self.contentStorage = contentStorage
        layoutManager.delegate = self
    }

    func loadMarkdown(_ markdown: String, into textStorage: NSTextStorage) {
        self.textStorage = textStorage
        blocks = BlockIndex.build(markdown: markdown)
        textStorage.setAttributedString(NSAttributedString(string: markdown))
        applyStyling(to: textStorage)
        invalidateLayout()
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
        blocks = BlockIndex.build(markdown: textStorage.string)
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

    func sourceLineMap() -> SourceLineMap {
        SourceLineMap(entries: packedSourceLineEntries())
    }

    func y(forSourceLine line: Int) -> CGFloat? {
        sourceLineMap().y(forSourceLine: line)
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
        let isHidden = hiddenUTF16Ranges.contains { hidden in
            NSIntersectionRange(hidden, fragmentRange).length == fragmentRange.length
        }
        guard isHidden else { return .visible }
        return placeholderUTF16Locations.contains(start) ? .placeholder : .collapsed
    }

    var hiddenUTF16RangeCount: Int { hiddenUTF16Ranges.count }

    private var documentString: String? {
        let string = textStorage?.string
            ?? contentStorage?.textStorage?.string
            ?? (layoutManager?.textContentManager as? NSTextContentStorage)?.textStorage?.string
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private var hiddenUTF16Ranges: [NSRange] {
        guard let string = documentString else { return [] }
        return foldStore.hiddenByteRanges(in: blocks).compactMap { bytes in
            let range = UTF8NSRange.nsRange(utf8Bytes: bytes, in: string)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return range
        }
    }

    /// The UTF-16 location of the first hidden line inside each folded
    /// fence's `foldExtent` — i.e. `foldExtent.lowerBound`, which
    /// `BlockIndex.build` always sets to the byte offset right after the
    /// opening fence line. That element becomes the placeholder instead of
    /// collapsing.
    private var placeholderUTF16Locations: Set<Int> {
        guard let string = documentString else { return [] }
        var locations: Set<Int> = []
        for block in blocks where block.id.kind == .fence {
            guard foldStore.isFolded(block.id), let extent = block.foldExtent else { continue }
            let range = UTF8NSRange.nsRange(utf8Bytes: extent.lowerBound..<extent.lowerBound, in: string)
            guard range.location != NSNotFound else { continue }
            locations.insert(range.location)
        }
        return locations
    }

    private func applyStyling(to textStorage: NSTextStorage) {
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
            let spans = MarkdownParser().previewSpans(textStorage.string)
            MarkdownPreviewRenderer.apply(spans: spans, to: textStorage, tokens: tokens, zoomScale: zoomScale)
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

    func drawFragments(in context: CGContext) {
        enumeratePackedVisibleFragments { fragment, packedY, _ in
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

    private func enumeratePackedVisibleFragments(
        _ body: (NSTextLayoutFragment, CGFloat, NSRange) -> Void
    ) {
        guard let layoutManager, let content = layoutManager.textContentManager else { return }
        var packedY: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let collapsed = (fragment as? FoldingTextLayoutFragment)?.isCollapsed ?? false
            if !collapsed {
                let utf16 = utf16Range(for: fragment, content: content)
                body(fragment, packedY, utf16)
                packedY += fragment.layoutFragmentFrame.height
            }
            return true
        }
    }

    private func packedVisibleFragments() -> [PackedFragment] {
        var packed: [PackedFragment] = []
        enumeratePackedVisibleFragments { fragment, packedY, utf16 in
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

    private func packedSourceLineEntries() -> [SourceLineMap.Entry] {
        guard let string = documentString else { return [] }

        let sourceMap = SourceMap(markdown: string)
        let hidden = hiddenUTF16Ranges
        let packed = packedVisibleFragments()
        var entries: [SourceLineMap.Entry] = []

        for line in 1...sourceMap.lineStarts.count {
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

    func gutterLineNumbers() -> [Int] {
        showLineNumbers ? visibleSourceLines : []
    }

    func foldableSourceLines() -> [Int] {
        let visible = Set(visibleSourceLines)
        return blocks.compactMap { block in
            guard block.foldExtent != nil, visible.contains(block.id.startLine) else { return nil }
            return block.id.startLine
        }
    }

    func toggleFold(atSourceLine line: Int) {
        guard let block = blocks.first(where: { $0.id.startLine == line && $0.foldExtent != nil }) else { return }
        foldStore.toggle(block.id)
        applyFolds()
        ensureLayout()
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

    func configureAsThemeCardSample() {
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
        drawGutter(in: context)
        context.saveGState()
        context.translateBy(x: gutterWidth, y: 0)
        session.drawFragments(in: context)
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
        drawGutter(in: context)
        context.saveGState()
        context.translateBy(x: gutterWidth, y: 0)
        session.drawFragments(in: context)
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
    }

    func setTheme(_ tokens: ThemeTokens) {
        session.setTheme(tokens, textStorage: documentTextStorage)
        paintCanvasBackground()
    }

    func setZoomScale(_ scale: CGFloat) {
        session.setZoomScale(scale, textStorage: documentTextStorage)
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
    }

    func unfoldAll() {
        session.unfoldAll(textStorage: documentTextStorage)
        ensureLayout()
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
        guard let line = sourceLine(atY: point.y), foldableSourceLines().contains(line) else { return true }
        toggleFold(atSourceLine: line)
        return true
    }

    private func drawGutter(in context: CGContext) {
        let gutterRect = CGRect(x: 0, y: 0, width: gutterWidth, height: max(bounds.height, layoutHeight))
        context.saveGState()
        #if os(macOS)
        NSColor.controlBackgroundColor.withAlphaComponent(0.35).setFill()
        #else
        UIColor.secondarySystemBackground.withAlphaComponent(0.35).setFill()
        #endif
        context.fill(gutterRect)

        let map = session.sourceLineMap()
        let foldable = Set(foldableSourceLines())
        let numberFont = PlatformFont.monospaced(size: 11)
        let numberColor = PlatformColor.secondaryLabel
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: numberColor,
        ]

        for entry in map.entries {
            if foldable.contains(entry.sourceLine) {
                drawChevron(
                    in: context,
                    at: CGPoint(x: 4, y: entry.y + max(2, (entry.height - 8) / 2)),
                    folded: blocks.first(where: { $0.id.startLine == entry.sourceLine }).map { foldStore.isFolded($0.id) } ?? false
                )
            }
            if showLineNumbers {
                let label = "\(entry.sourceLine)" as NSString
                let size = label.size(withAttributes: numberAttrs)
                let x = GutterMetrics.chevronWidth + GutterMetrics.numberWidth - 6 - size.width
                let y = entry.y + max(0, (min(entry.height, size.height + 4) - size.height) / 2)
                label.draw(at: CGPoint(x: x, y: y), withAttributes: numberAttrs)
            }
        }
        context.restoreGState()
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

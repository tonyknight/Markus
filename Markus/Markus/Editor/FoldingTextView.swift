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
    var isCollapsed = false

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
        super.draw(at: point, in: context)
    }
}

@MainActor
final class FoldingSession: NSObject, NSTextLayoutManagerDelegate {
    let foldStore: FoldStore
    private(set) var blocks: [Block] = []
    private(set) var mode: EditorMode
    private(set) var collapsedFragmentCount = 0
    private weak var layoutManager: NSTextLayoutManager?
    private weak var contentStorage: NSTextContentStorage?
    private weak var textStorage: NSTextStorage?

    init(foldStore: FoldStore = FoldStore(), mode: EditorMode = .preview) {
        self.foldStore = foldStore
        self.mode = mode
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

    func applyFolds() {
        collapsedFragmentCount = 0
        if let textStorage {
            applyStyling(to: textStorage)
        }
        invalidateLayout()
    }

    func ensureLayout() {
        guard let layoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        recountCollapsedFragments()
    }

    var layoutHeight: CGFloat {
        packedLayoutHeight()
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = FoldingTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.isCollapsed = isElementCollapsed(textElement, layoutManager: textLayoutManager)
        return fragment
    }

    private func isElementCollapsed(_ textElement: NSTextElement, layoutManager: NSTextLayoutManager) -> Bool {
        guard let elementRange = textElement.elementRange,
              let content = layoutManager.textContentManager
        else {
            return false
        }
        let start = content.offset(from: content.documentRange.location, to: elementRange.location)
        let end = content.offset(from: content.documentRange.location, to: elementRange.endLocation)
        let fragmentRange = NSRange(location: start, length: max(0, end - start))
        guard fragmentRange.length > 0 else { return false }
        return hiddenUTF16Ranges.contains { hidden in
            NSIntersectionRange(hidden, fragmentRange).length == fragmentRange.length
        }
    }

    var hiddenUTF16RangeCount: Int { hiddenUTF16Ranges.count }

    private var hiddenUTF16Ranges: [NSRange] {
        let string = textStorage?.string
            ?? contentStorage?.textStorage?.string
            ?? (layoutManager?.textContentManager as? NSTextContentStorage)?.textStorage?.string
        guard let string, !string.isEmpty else { return [] }
        return foldStore.hiddenByteRanges(in: blocks).compactMap { bytes in
            let range = UTF8NSRange.nsRange(utf8Bytes: bytes, in: string)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return range
        }
    }

    private func applyStyling(to textStorage: NSTextStorage) {
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        switch mode {
        case .source:
            let source = [
                NSAttributedString.Key.font: PlatformFont.monospaced(size: 14),
                NSAttributedString.Key.foregroundColor: PlatformColor.label,
            ]
            textStorage.setAttributes(source, range: full)
        case .preview:
            let body = [
                NSAttributedString.Key.font: PlatformFont.body(size: 16),
                NSAttributedString.Key.foregroundColor: PlatformColor.label,
            ]
            textStorage.setAttributes(body, range: full)
            let spans = MarkdownParser().previewSpans(textStorage.string)
            MarkdownPreviewRenderer.apply(spans: spans, to: textStorage)
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
        guard let layoutManager else { return }
        var y: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let collapsed = (fragment as? FoldingTextLayoutFragment)?.isCollapsed ?? false
            if !collapsed {
                fragment.draw(at: CGPoint(x: fragment.layoutFragmentFrame.minX, y: y), in: context)
                y += fragment.layoutFragmentFrame.height
            }
            return true
        }
    }

    private func packedLayoutHeight() -> CGFloat {
        guard let layoutManager else { return 0 }
        var height: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let collapsed = (fragment as? FoldingTextLayoutFragment)?.isCollapsed ?? false
            if !collapsed {
                height += fragment.layoutFragmentFrame.height
            }
            return true
        }
        return height
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
    var string: String {
        get { documentTextStorage.string }
        set { loadMarkdown(newValue) }
    }
    var onTextDidChange: (() -> Void)?

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
        #if os(macOS)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        #else
        backgroundColor = .systemBackground
        isOpaque = true
        #endif
    }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { editingUndoManager }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        session.drawFragments(in: context)
    }
    #else
    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { editingUndoManager }

    override func draw(_ rect: CGRect) {
        backgroundColor?.setFill()
        UIRectFill(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        session.drawFragments(in: context)
    }
    #endif

    func loadMarkdown(_ markdown: String) {
        session.loadMarkdown(markdown, into: documentTextStorage)
    }

    func setMode(_ mode: EditorMode) {
        session.setMode(mode, textStorage: documentTextStorage)
    }

    func applyFolds() {
        session.applyFolds()
    }

    func ensureLayout() {
        session.ensureLayout()
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
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

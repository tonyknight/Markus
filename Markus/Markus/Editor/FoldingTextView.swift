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
        applyCollapsedParagraphStyles(to: textStorage)
        invalidateLayout()
    }

    func applyFolds() {
        collapsedFragmentCount = 0
        if let textStorage {
            applyStyling(to: textStorage)
            applyCollapsedParagraphStyles(to: textStorage)
        }
        invalidateLayout()
    }

    func ensureLayout() {
        guard let layoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
    }

    var layoutHeight: CGFloat {
        layoutManager?.usageBoundsForTextContainer.height ?? 0
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = FoldingTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.isCollapsed = isElementCollapsed(textElement, layoutManager: textLayoutManager)
        if fragment.isCollapsed {
            collapsedFragmentCount += 1
        }
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
            for block in blocks {
                let nsRange = UTF8NSRange.nsRange(utf8Bytes: block.bytes, in: textStorage.string)
                guard nsRange.location != NSNotFound else { continue }
                switch block.kind {
                case .heading:
                    textStorage.addAttributes([
                        .font: PlatformFont.heading(size: 22),
                        .foregroundColor: PlatformColor.label,
                    ], range: nsRange)
                case .fencedCode:
                    textStorage.addAttributes([
                        .font: PlatformFont.monospaced(size: 13),
                    ], range: nsRange)
                case .other:
                    break
                }
            }
        }
        textStorage.endEditing()
    }

    private func applyCollapsedParagraphStyles(to textStorage: NSTextStorage) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        for range in hiddenUTF16Ranges {
            guard NSMaxRange(range) <= textStorage.length else { continue }
            textStorage.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    private func invalidateLayout() {
        guard let layoutManager else { return }
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
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
#else
typealias PlatformFontType = UIFont
typealias PlatformColorType = UIColor
#endif

#if os(macOS)
@MainActor
final class FoldingTextView: NSTextView {
    var session: FoldingSession

    var foldStore: FoldStore { session.foldStore }
    var blocks: [Block] { session.blocks }
    var layoutHeight: CGFloat { session.layoutHeight }
    var collapsedFragmentCount: Int { session.collapsedFragmentCount }
    var hiddenRangeCount: Int { session.hiddenUTF16RangeCount }

    convenience init(foldStore: FoldStore = FoldStore()) {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        self.init(frame: NSRect(x: 0, y: 0, width: 480, height: 800), textContainer: container)
        session = FoldingSession(foldStore: foldStore)
        if let viewManager = textLayoutManager {
            let content = (viewManager.textContentManager as? NSTextContentStorage) ?? contentStorage
            if content.textStorage == nil {
                content.textStorage = textStorage
            }
            session.attach(layoutManager: viewManager, contentStorage: content)
        } else {
            if contentStorage.textStorage == nil {
                contentStorage.textStorage = textStorage
            }
            session.attach(layoutManager: layoutManager, contentStorage: contentStorage)
        }
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        session = FoldingSession()
        super.init(frame: frameRect, textContainer: container)
        completeInit()
    }

    required init?(coder: NSCoder) {
        session = FoldingSession()
        super.init(coder: coder)
        completeInit()
    }

    private func completeInit() {
        isRichText = false
        allowsUndo = true
        isEditable = true
        font = PlatformFont.monospaced(size: 14)
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = false
        textContainer?.widthTracksTextView = false
        frame = NSRect(x: 0, y: 0, width: 480, height: 800)
        attachSession()
    }

    private func attachSession() {
        guard let layoutManager = textLayoutManager,
              let content = layoutManager.textContentManager as? NSTextContentStorage
        else {
            return
        }
        session.attach(layoutManager: layoutManager, contentStorage: content)
    }

    func loadMarkdown(_ markdown: String) {
        let storage = documentTextStorage
        session.loadMarkdown(markdown, into: storage)
    }

    func setMode(_ mode: EditorMode) {
        session.setMode(mode, textStorage: documentTextStorage)
        isEditable = (mode == .source)
    }

    var documentTextStorage: NSTextStorage {
        if let textStorage {
            return textStorage
        }
        if let storage = (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage {
            return storage
        }
        let storage = NSTextStorage()
        (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage = storage
        return storage
    }

    func applyFolds() {
        attachSession()
        session.applyFolds()
    }

    func ensureLayout() {
        attachSession()
        session.ensureLayout()
        layoutSubtreeIfNeeded()
    }

    private var hostWindow: NSWindow?

    func prepareForEditing() {
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
    }

    func insertTextAtCaret(_ string: String) {
        prepareForEditing()
        let range = NSRange(location: 0, length: 0)
        setSelectedRange(range)
        if shouldChangeText(in: range, replacementString: string) {
            textStorage?.replaceCharacters(in: range, with: string)
            didChangeText()
        }
    }

    func undoLastChange() -> Bool {
        guard let undoManager, undoManager.canUndo else { return false }
        undoManager.undo()
        return true
    }
}

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

@MainActor
final class FoldingTextView: UITextView {
    var session: FoldingSession

    var foldStore: FoldStore { session.foldStore }
    var blocks: [Block] { session.blocks }
    var layoutHeight: CGFloat { session.layoutHeight }
    var collapsedFragmentCount: Int { session.collapsedFragmentCount }
    var hiddenRangeCount: Int { session.hiddenUTF16RangeCount }
    var string: String {
        get { text }
        set { text = newValue }
    }

    convenience init(foldStore: FoldStore = FoldStore()) {
        self.init(frame: CGRect(x: 0, y: 0, width: 480, height: 800), textContainer: nil)
        session = FoldingSession(foldStore: foldStore)
        attachSession()
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        session = FoldingSession()
        super.init(frame: frame, textContainer: textContainer)
        completeInit()
    }

    required init?(coder: NSCoder) {
        session = FoldingSession()
        super.init(coder: coder)
        completeInit()
    }

    private func completeInit() {
        isEditable = true
        font = PlatformFont.monospaced(size: 14)
        frame = CGRect(x: 0, y: 0, width: 480, height: 800)
        textContainer.size = CGSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
        attachSession()
    }

    private func attachSession() {
        guard let layoutManager = textLayoutManager,
              let content = layoutManager.textContentManager as? NSTextContentStorage
        else {
            return
        }
        session.attach(layoutManager: layoutManager, contentStorage: content)
    }

    func loadMarkdown(_ markdown: String) {
        session.loadMarkdown(markdown, into: textStorage)
    }

    func setMode(_ mode: EditorMode) {
        session.setMode(mode, textStorage: textStorage)
        isEditable = (mode == .source)
    }

    func applyFolds() {
        attachSession()
        session.applyFolds()
    }

    func ensureLayout() {
        attachSession()
        session.ensureLayout()
        layoutIfNeeded()
    }

    private var hostWindow: UIWindow?

    func prepareForEditing() {
        let window = UIWindow(frame: frame)
        let host = UIViewController()
        host.view.frame = frame
        host.view.addSubview(self)
        window.rootViewController = host
        window.makeKeyAndVisible()
        becomeFirstResponder()
        hostWindow = window
    }

    func insertTextAtCaret(_ string: String) {
        prepareForEditing()
        let range = NSRange(location: 0, length: 0)
        selectedRange = range
        if shouldChangeText(in: range, replacementText: string) {
            textStorage.replaceCharacters(in: range, with: string)
            delegate?.textViewDidChange?(self)
        }
    }

    func undoLastChange() -> Bool {
        guard let undoManager, undoManager.canUndo else { return false }
        undoManager.undo()
        return true
    }
}

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

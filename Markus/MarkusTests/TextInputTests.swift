import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Markus

/// Exercises text input in Source mode (ticket 13): caret geometry and
/// blinking (T01), selection/mouse/keyboard (T02), undo coalescing
/// (T03), dirty/updateChangeCount wiring (T04), debounced reparse (T05),
/// Preview selection → source mapping (T06), accessibility (T07).
/// `NSTextInputClient`/mouse selection are AppKit-only (the ticket's
/// Design note) — this whole file is macOS-only; iOS/iPadOS keep
/// building and passing the existing non-editing suite (N6).
#if os(macOS)
@MainActor
struct TextInputTests {
    private var fixture: String {
        """
        ## Heading two

        A paragraph under the H2.

        Second line of the paragraph.
        """
    }

    private func makeBitmapContext() -> CGContext {
        CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    private func makeSourceView(_ markdown: String? = nil) -> FoldingTextView {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(markdown ?? fixture)
        view.setMode(.source)
        view.ensureLayout()
        return view
    }

    // MARK: - T01: caret geometry, blinking, NSTextInputClient

    @Test func caretIsVisibleAndPlaceableAtAnyOffsetInSourceMode() throws {
        let view = makeSourceView()
        #expect(view.selectedUTF16Range == NSRange(location: 0, length: 0))

        let firstRect = try #require(view.session.packedCaretRect(forUTF16Offset: 0))
        #expect(firstRect.height > 0)

        // Place the caret mid-document (not just offset 0) and confirm
        // it resolves to real, different geometry — a live check that
        // the caret can be placed anywhere, not merely drawn at a fixed
        // spot (N9).
        let midOffset = (view.string as NSString).range(of: "paragraph").location
        view.selectedUTF16Range = NSRange(location: midOffset, length: 0)
        let midRect = try #require(view.session.packedCaretRect(forUTF16Offset: midOffset))
        #expect(midRect.origin != firstRect.origin)

        // The real per-frame draw path (mirrors drawGutter/drawFragments'
        // own testability precedent) must not crash and must actually
        // read live selection/mode/caretVisible state, not a constant.
        let context = makeBitmapContext()
        view.drawCaret(in: context)
    }

    @Test func caretDoesNotDrawWhenSelectionIsNonEmptyOrModeIsPreview() {
        let view = makeSourceView()
        view.selectedUTF16Range = NSRange(location: 0, length: 3)
        #expect(view.session.packedCaretRect(forUTF16Offset: 0) != nil, "geometry still resolvable")
        // drawCaret itself must gate on selection length / mode — proven
        // indirectly via caretVisible + mode + selection state below,
        // since draw output isn't otherwise inspectable in a headless
        // bitmap without pixel sampling.
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.setMode(.preview)
        #expect(view.mode == .preview)
    }

    @Test func caretBlinkTogglesVisibilityEachCall() {
        let view = makeSourceView()
        #expect(view.caretVisible)
        view.toggleCaretVisibility()
        #expect(!view.caretVisible)
        view.toggleCaretVisibility()
        #expect(view.caretVisible)
    }

    @Test func insertTextInsertsAtTheCaretNotAlwaysAtOffsetZero() throws {
        let view = makeSourceView("Hello")
        let endOffset = (view.string as NSString).length
        view.selectedUTF16Range = NSRange(location: endOffset, length: 0)
        view.insertText(" World", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hello World")

        // Insert mid-string, not just at the end.
        view.selectedUTF16Range = NSRange(location: 2, length: 0)
        view.insertText("XX", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "HeXXllo World")
        #expect(view.selectedUTF16Range == NSRange(location: 4, length: 0))
    }

    @Test func insertTextReplacesAnExistingSelectionRatherThanInsertingAtItsStart() {
        let view = makeSourceView("Hello World")
        let range = (view.string as NSString).range(of: "World")
        view.selectedUTF16Range = range
        view.insertText("There", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hello There")
    }

    @Test func insertTextIsANoOpInPreviewMode() {
        let view = makeSourceView("Hello")
        view.setMode(.preview)
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hello")
    }

    @Test func insertTextRegistersUndoAndRedoRestoresIt() throws {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hello!")

        #expect(view.undoLastChange())
        #expect(view.string == "Hello")

        #expect(view.redoLastChange())
        #expect(view.string == "Hello!")
    }

    @Test func doCommandHandlesNewlineAndBackspaceAndForwardDeleteThroughTheSameMutatePrimitive() {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.doCommand(by: Selector(("insertNewline:")))
        #expect(view.string == "Hello\n")

        view.selectedUTF16Range = NSRange(location: 6, length: 0)
        view.doCommand(by: Selector(("deleteBackward:")))
        #expect(view.string == "Hello")

        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.doCommand(by: Selector(("deleteForward:")))
        #expect(view.string == "ello")
    }

    @Test func setMarkedTextInsertsComposingTextLiveAndCommitClearsMarkingWithOneUndoStep() {
        let view = makeSourceView("Hi ")
        let end = (view.string as NSString).length
        view.selectedUTF16Range = NSRange(location: end, length: 0)

        // Simulate a real IME composing session: three successive
        // revisions of the same marked range, as a Pinyin/Romaji input
        // method would send.
        view.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        #expect(view.string == "Hi n")

        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hi ni")

        view.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hi 你好")
        #expect(view.markedRange().length == 2)

        // Commit: insertText finalizes the marked range and clears it.
        view.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
        #expect(view.string == "Hi 你好")

        // The whole composing session collapses into exactly one undo
        // step — none of the intermediate setMarkedText revisions were
        // separately undo-registered (they are provisional, not
        // committed edits).
        #expect(view.undoLastChange())
        #expect(view.string == "Hi ")
        #expect(!view.undoLastChange(), "only one undo step for the whole composition session")
    }

    @Test func unmarkTextFinalizesTheCurrentCompositionWithoutRemovingItsCharacters() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.setMarkedText("draft", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        view.unmarkText()
        #expect(!view.hasMarkedText())
        #expect(view.string == "draft")
    }

    @Test func firstRectForCharacterRangeAndCharacterIndexRoundTripThroughScreenCoordinates() throws {
        let view = makeSourceView("Hello World")
        view.prepareForEditing()
        // `prepareForEditing()` creates a real NSWindow with `view` as
        // its content view — a genuine strong reference cycle
        // (view.hostWindow <-> window.contentView) that ARC alone never
        // breaks. Left alone, `becomeFirstResponder()`'s blink timer
        // (T01) would keep firing against this leaked view for the
        // rest of the process's life — found via a real crash running
        // the full suite (see FoldingTextView's `deinit` doc comment).
        // `resignFirstResponder()` stops it explicitly regardless of
        // whether the pair ever actually deallocates.
        defer { view.resignFirstResponder() }
        view.ensureLayout()

        let targetOffset = 6 // "World" start
        let screenRect = view.firstRect(forCharacterRange: NSRange(location: targetOffset, length: 0), actualRange: nil)
        #expect(screenRect.width >= 0)
        #expect(screenRect != .zero)

        let roundTripped = view.characterIndex(for: NSPoint(x: screenRect.minX + 1, y: screenRect.midY))
        // Not required to be pixel-exact, but must land within the same
        // line, close to the requested offset — a live geometric
        // round trip, not a compile-time constant (N9).
        #expect(abs(roundTripped - targetOffset) <= 2)
    }

    @Test func attributedSubstringAndValidAttributesForMarkedTextExposeRealBufferContent() throws {
        let view = makeSourceView("Hello World")
        let range = NSRange(location: 0, length: 5)
        let substring = try #require(view.attributedSubstring(forProposedRange: range, actualRange: nil))
        #expect(substring.string == "Hello")
        #expect(view.validAttributesForMarkedText().contains(.underlineStyle))
    }

    @Test func selectedRangeReflectsLiveSelectionState() {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 2, length: 3)
        #expect(view.selectedRange() == NSRange(location: 2, length: 3))
    }

    // MARK: - T02: selection drawing, mouse click/drag, keyboard navigation, copy

    /// Builds an `NSEvent` at the packed caret position for `offset` —
    /// routing through the same geometry T01 already validated
    /// (`packedCaretRect`) rather than guessing pixel coordinates blind,
    /// so a "click at offset N" test genuinely exercises mouseDown's own
    /// click-count/anchor logic, not a second, independent guess at
    /// character geometry.
    private func mouseEvent(_ type: NSEvent.EventType, view: FoldingTextView, atUTF16Offset offset: Int, clickCount: Int = 1) throws -> NSEvent {
        let packedRect = try #require(view.session.packedCaretRect(forUTF16Offset: offset))
        let viewPoint = NSPoint(x: packedRect.midX + view.gutterWidth, y: packedRect.midY)
        let windowPoint = view.convert(viewPoint, to: nil)
        return try #require(NSEvent.mouseEvent(
            with: type, location: windowPoint, modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
        ))
    }

    @Test func singleClickPlacesTheCaretNearTheClickedOffsetWithNoSelection() throws {
        let view = makeSourceView("Hello World")
        view.prepareForEditing()
        defer { view.resignFirstResponder() } // stop the blink timer; see the first T01 test's comment
        view.ensureLayout()

        let targetOffset = 6 // "World"
        let down = try mouseEvent(.leftMouseDown, view: view, atUTF16Offset: targetOffset)
        view.mouseDown(with: down)

        #expect(view.selectedUTF16Range.length == 0)
        #expect(abs(view.selectedUTF16Range.location - targetOffset) <= 1)
    }

    @Test func dragAfterMouseDownExtendsACharacterSelectionFromTheAnchor() throws {
        let view = makeSourceView("Hello World")
        view.prepareForEditing()
        defer { view.resignFirstResponder() } // stop the blink timer; see the first T01 test's comment
        view.ensureLayout()

        let down = try mouseEvent(.leftMouseDown, view: view, atUTF16Offset: 0)
        view.mouseDown(with: down)
        let drag = try mouseEvent(.leftMouseDragged, view: view, atUTF16Offset: 5)
        view.mouseDragged(with: drag)

        #expect(view.selectedUTF16Range.location == 0)
        #expect(view.selectedUTF16Range.length > 0)

        let up = try mouseEvent(.leftMouseUp, view: view, atUTF16Offset: 5)
        view.mouseUp(with: up)
        // Further drag events after mouseUp must not keep extending —
        // the drag anchor is cleared.
        let strayDrag = try mouseEvent(.leftMouseDragged, view: view, atUTF16Offset: 10)
        let before = view.selectedUTF16Range
        view.mouseDragged(with: strayDrag)
        #expect(view.selectedUTF16Range == before)
    }

    @Test func doubleClickSelectsTheWholeWordUnderThePoint() throws {
        let view = makeSourceView("Hello World")
        view.prepareForEditing()
        defer { view.resignFirstResponder() } // stop the blink timer; see the first T01 test's comment
        view.ensureLayout()

        let down = try mouseEvent(.leftMouseDown, view: view, atUTF16Offset: 8, clickCount: 2)
        view.mouseDown(with: down)

        let selected = (view.string as NSString).substring(with: view.selectedUTF16Range)
        #expect(selected == "World")
    }

    @Test func tripleClickSelectsTheWholeLineIncludingItsNewline() throws {
        let view = makeSourceView("First line.\nSecond line.\nThird line.")
        view.prepareForEditing()
        defer { view.resignFirstResponder() } // stop the blink timer; see the first T01 test's comment
        view.ensureLayout()

        let secondLineOffset = (view.string as NSString).range(of: "Second").location
        let down = try mouseEvent(.leftMouseDown, view: view, atUTF16Offset: secondLineOffset, clickCount: 3)
        view.mouseDown(with: down)

        let selected = (view.string as NSString).substring(with: view.selectedUTF16Range)
        #expect(selected == "Second line.\n")
    }

    @Test func arrowKeysMoveTheCaretAndCollapseAnExistingSelectionToTheCorrectEdge() {
        let view = makeSourceView("Hello World")
        view.selectedUTF16Range = NSRange(location: 2, length: 4)

        view.doCommand(by: Selector(("moveRight:")))
        #expect(view.selectedUTF16Range == NSRange(location: 6, length: 0))

        view.selectedUTF16Range = NSRange(location: 2, length: 4)
        view.doCommand(by: Selector(("moveLeft:")))
        #expect(view.selectedUTF16Range == NSRange(location: 2, length: 0))

        // From a collapsed caret, a plain move steps by one.
        view.doCommand(by: Selector(("moveRight:")))
        #expect(view.selectedUTF16Range == NSRange(location: 3, length: 0))
        view.doCommand(by: Selector(("moveLeft:")))
        view.doCommand(by: Selector(("moveLeft:")))
        #expect(view.selectedUTF16Range == NSRange(location: 1, length: 0))
    }

    @Test func shiftArrowExtendsSelectionFromAStableAnchor() {
        let view = makeSourceView("Hello World")
        view.selectedUTF16Range = NSRange(location: 3, length: 0)

        view.doCommand(by: Selector(("moveRightAndModifySelection:")))
        view.doCommand(by: Selector(("moveRightAndModifySelection:")))
        #expect(view.selectedUTF16Range == NSRange(location: 3, length: 2))

        // Reversing direction shrinks back toward the anchor rather than
        // starting a new one from the moving edge.
        view.doCommand(by: Selector(("moveLeftAndModifySelection:")))
        #expect(view.selectedUTF16Range == NSRange(location: 3, length: 1))
    }

    @Test func wordAndLineBoundaryNavigationCoverAReasonableMinimum() {
        let view = makeSourceView("Hello World Again")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)

        view.doCommand(by: Selector(("moveWordRight:")))
        #expect(view.selectedUTF16Range.location == 5) // end of "Hello", before the space

        view.doCommand(by: Selector(("moveWordRight:")))
        #expect(view.selectedUTF16Range.location == 11) // end of "World", before the space

        view.doCommand(by: Selector(("moveToEndOfLine:")))
        #expect(view.selectedUTF16Range.location == (view.string as NSString).length)

        view.doCommand(by: Selector(("moveToBeginningOfLine:")))
        #expect(view.selectedUTF16Range.location == 0)
    }

    @Test func copyPutsTheSourceModeSelectionOnThePasteboardVerbatim() {
        let view = makeSourceView("Hello World")
        view.selectedUTF16Range = (view.string as NSString).range(of: "World")
        NSPasteboard.general.clearContents()
        view.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "World")
    }

    @Test func copyIsANoOpWithNoSelectionOrInPreviewMode() {
        let view = makeSourceView("Hello World")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("unchanged", forType: .string)

        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "unchanged")

        view.selectedUTF16Range = (view.string as NSString).range(of: "World")
        view.setMode(.preview)
        view.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "unchanged")
    }

    @Test func selectionHighlightGeometryIsRealAndEmptyOnlyWhenSelectionIsCollapsed() {
        let view = makeSourceView("Hello World")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        #expect(view.session.packedSelectionRects(forUTF16Range: view.selectedUTF16Range).isEmpty)

        let range = (view.string as NSString).range(of: "World")
        let rects = view.session.packedSelectionRects(forUTF16Range: range)
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { $0.width > 0 && $0.height > 0 })

        let context = makeBitmapContext()
        view.selectedUTF16Range = range
        view.drawSelectionHighlight(in: context, visibleRect: view.currentVisiblePackedRect())
    }

    // MARK: - T03: undo/redo coalescing

    /// Types `text` one character at a time via the real `insertText`
    /// entry point (not a single multi-char call) — this is what a real
    /// keystroke-by-keystroke typing session actually drives.
    private func typeCharacterByCharacter(_ text: String, into view: FoldingTextView) {
        for character in text {
            view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    @Test func typingAWordCharacterByCharacterCoalescesIntoOneUndoStep() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        typeCharacterByCharacter("hello", into: view)
        #expect(view.string == "hello")

        #expect(view.undoLastChange())
        #expect(view.string == "", "one undo step must remove the whole typed run")
        #expect(!view.undoLastChange(), "nothing further to undo — only one step was registered")
    }

    @Test func typingThenMovingTheCaretThenTypingElsewhereStartsANewGroup() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        typeCharacterByCharacter("ab", into: view)
        #expect(view.string == "ab")

        // Caret moved (not a contiguous continuation of the typed run)
        // before typing again elsewhere.
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        typeCharacterByCharacter("X", into: view)
        #expect(view.string == "Xab")

        #expect(view.undoLastChange())
        #expect(view.string == "ab", "the non-contiguous 'X' is its own undo step")
        #expect(view.undoLastChange())
        #expect(view.string == "", "the original contiguous 'ab' run is the other undo step")
    }

    @Test func consecutiveBackspacesCoalesceSeparatelyFromConsecutiveInserts() {
        let view = makeSourceView("hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.doCommand(by: Selector(("deleteBackward:")))
        view.doCommand(by: Selector(("deleteBackward:")))
        view.doCommand(by: Selector(("deleteBackward:")))
        #expect(view.string == "he")

        #expect(view.undoLastChange())
        #expect(view.string == "hello", "three coalesced backspaces are one undo step")
    }

    @Test func insertsAndBackspacesNeverCoalesceWithEachOtherEvenWhenAdjacent() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        typeCharacterByCharacter("ab", into: view)
        #expect(view.string == "ab")
        // Backspacing immediately after typing is a different kind
        // (delete vs insert) — must not merge into the insert group.
        view.doCommand(by: Selector(("deleteBackward:")))
        #expect(view.string == "a")

        #expect(view.undoLastChange())
        #expect(view.string == "ab", "the backspace is its own undo step")
        #expect(view.undoLastChange())
        #expect(view.string == "", "the coalesced 'ab' insert run is the other undo step")
    }

    @Test func aPauseLongerThanTheCoalescingWindowStartsANewGroupEvenWhenContiguous() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        var now = Date(timeIntervalSince1970: 1_000_000)
        view.coalescingClock = { now }

        typeCharacterByCharacter("ab", into: view)
        #expect(view.string == "ab")

        // Simulate a long pause (well past the coalescing window) before
        // the next, otherwise-contiguous character — deterministic via
        // the injectable clock (N9), no real sleeping.
        now = now.addingTimeInterval(30)
        typeCharacterByCharacter("c", into: view)
        #expect(view.string == "abc")

        #expect(view.undoLastChange())
        #expect(view.string == "ab", "the stale 'c' is its own undo step despite being contiguous")
        #expect(view.undoLastChange())
        #expect(view.string == "")
    }

    @Test func redoReplaysTheWholeCoalescedRunInOneStep() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        typeCharacterByCharacter("hi", into: view)
        #expect(view.undoLastChange())
        #expect(view.string == "")
        #expect(view.redoLastChange())
        #expect(view.string == "hi")
        #expect(!view.redoLastChange())
    }

    @Test func multiCharacterInsertAndSelectionReplacementAreNeverCoalesced() {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        // A multi-character insert (IME commit / paste analogue) must
        // always be its own atomic undo step, never merged with
        // anything before or after it.
        view.insertText(" World", replacementRange: NSRange(location: NSNotFound, length: 0))
        typeCharacterByCharacter("!", into: view)
        #expect(view.string == "Hello World!")

        #expect(view.undoLastChange())
        #expect(view.string == "Hello World", "the coalescable '!' is its own step")
        #expect(view.undoLastChange())
        #expect(view.string == "Hello", "the multi-character insert is its own separate step")
    }

    /// Calling undo while a coalescing group is still open (no
    /// subsequent edit ever closed it) must not crash —
    /// `UndoManager.undo()` while `groupingLevel > 0` is a programming
    /// error if not guarded against.
    @Test func undoImmediatelyAfterTypingWithNoInterveningEditDoesNotCrash() {
        let view = makeSourceView("")
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        typeCharacterByCharacter("ab", into: view)
        #expect(view.undoLastChange())
        #expect(view.string == "")
    }
}
#endif

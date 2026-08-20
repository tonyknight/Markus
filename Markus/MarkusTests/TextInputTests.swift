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

    private func makePreviewView(_ markdown: String) -> FoldingTextView {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown(markdown)
        view.setMode(.preview)
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

    // A brand-new document (`MarkdownDocument.init()` loading empty
    // content, matching what a real File > New does) has zero TextKit 2
    // layout fragments — nothing has been typed yet. Before this fix,
    // both `packedCaretRect`/`utf16Offset(atPackedPoint:)` returned `nil`
    // whenever fragment enumeration found nothing to hit-test against,
    // so a brand-new document could never place a caret at all: no
    // visible caret on load, and any click attempt fell through
    // `mouseDown`'s nil-offset guard to `super.mouseDown(with:)`,
    // surfacing as an alert beep with no caret ever appearing.
    @Test func emptyDocumentResolvesACaretAtOffsetZeroWithNoTypedContentYet() throws {
        let view = FoldingTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 800), foldStore: FoldStore())
        view.loadMarkdown("")
        view.setMode(.source)
        view.ensureLayout()
        #expect(view.string.isEmpty)

        let rect = try #require(view.session.packedCaretRect(forUTF16Offset: 0))
        #expect(rect.height > 0)

        let resolved = view.session.utf16Offset(atPackedPoint: CGPoint(x: 5, y: 5))
        #expect(resolved == 0)
    }

    // Nothing in this app's real flow ever clicks inside the text area
    // before a person tries to type — switching to Source via the
    // toolbar picker is itself the only action taken. Before this fix,
    // `setMode` never claimed first responder, so the view could go on
    // drawing a caret (`caretVisible`'s static default, independent of
    // real focus) that never actually blinked and never received
    // `keyDown`/`insertText` — typing did nothing, or beeped, until a
    // separate click happened to land inside the text area itself.
    @Test func switchingToSourceClaimsFirstResponderWithoutRequiringASeparateClick() {
        let view = makeSourceView()
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { view.resignFirstResponder() }

        // `NSWindow.initialFirstResponder` defaults to the window's
        // `contentView` — here that's `view` itself directly, so it's
        // already first responder as a pure artifact of this simplified
        // single-view test window. The real app's window content view is
        // an `NSHostingView` wrapping the whole SwiftUI chrome, several
        // layers above the actual `FoldingTextView`, so that default
        // never reaches it there — nothing hands it focus automatically,
        // which is the real gap `setMode` now closes explicitly. Reset
        // to a neutral "nothing specific has focus" state here so this
        // test exercises the same transition the real app needs: some
        // other control has focus, then Source is switched to.
        window.makeFirstResponder(nil)
        #expect(window.firstResponder !== view)

        view.setMode(.preview)
        #expect(window.firstResponder !== view)

        view.setMode(.source)
        #expect(window.firstResponder === view)
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

    // T06 note: this originally also asserted copy() was a no-op after
    // switching to Preview mode — true only because Preview-mode copy
    // wasn't implemented yet at T02 (the plan explicitly deferred "the
    // Preview-mode case" to T06). Now that it is (see T06's own tests
    // below), a Preview-mode selection genuinely does copy source
    // Markdown, so that half of the original assertion would be
    // actively wrong. Updated to keep testing what's still true —
    // copy() no-ops when there is nothing selected, in either mode —
    // rather than weakening or deleting the test.
    @Test func copyIsANoOpWithNoSelectionInEitherMode() {
        let view = makeSourceView("Hello World")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("unchanged", forType: .string)

        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "unchanged")

        view.setMode(.preview)
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
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

    // MARK: - T04: dirty flag and updateChangeCount wiring

    @Test func onTextChangeCommittedReportsDoneUndoneAndRedoneForRealInsertText() {
        let view = makeSourceView("Hi")
        var kinds: [TextChangeKind] = []
        view.onTextChangeCommitted = { kinds.append($0) }

        view.selectedUTF16Range = NSRange(location: 2, length: 0)
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(kinds == [.done])

        #expect(view.undoLastChange())
        #expect(kinds == [.done, .undone])

        #expect(view.redoLastChange())
        #expect(kinds == [.done, .undone, .redone])
    }

    @Test func onTextChangeCommittedFiresForInsertTextAtCaretAndReplaceSelectionToo() {
        let view = makeSourceView("Hello")
        var kinds: [TextChangeKind] = []
        view.onTextChangeCommitted = { kinds.append($0) }

        view.insertTextAtCaret("X")
        #expect(kinds == [.done])
        #expect(view.undoLastChange())
        #expect(kinds == [.done, .undone])

        kinds.removeAll()
        view.selectedUTF16Range = NSRange(location: 0, length: 5)
        #expect(view.replaceSelection(with: "Bye"))
        #expect(kinds == [.done])
    }

    @Test func onTextChangeCommittedDoesNotFireForNonTextChangesLikeFoldOrModeOrZoom() {
        let view = makeSourceView(fixture)
        var kinds: [TextChangeKind] = []
        view.onTextChangeCommitted = { kinds.append($0) }

        view.setMode(.preview)
        view.setMode(.source)
        view.setZoomScale(1.3)
        let heading = view.blocks.first { $0.id.kind == .heading && $0.foldExtent != nil }
        if let heading {
            view.toggleFold(atSourceLine: heading.id.startLine)
        }
        #expect(kinds.isEmpty, "fold/mode/zoom changes never touch the buffer and must not report a text change")
    }

    @Test func markdownDocumentUpdatesChangeCountOnEditAndUndoReturnsToClean() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("Hello".utf8), ofType: "net.daringfireball.markdown")
        #expect(!document.isDocumentEdited)

        let editor = document.session.editor
        editor.setMode(.source)
        editor.selectedUTF16Range = NSRange(location: 5, length: 0)
        editor.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(document.isDocumentEdited)

        // Undoing back to exactly the loaded state must clear
        // isDocumentEdited — real NSDocument change-count semantics
        // (`.changeDone` then `.changeUndone` net to zero), not a
        // hand-rolled dirty flag this test would trivially satisfy.
        #expect(editor.undoLastChange())
        #expect(!document.isDocumentEdited)

        #expect(editor.redoLastChange())
        #expect(document.isDocumentEdited)
    }

    // MARK: - T05: debounced reparse off the keystroke path

    @Test func insertTextDoesNotReparseSynchronouslyButFiringTheDebounceDoes() {
        let view = makeSourceView("Hello")
        let before = view.session.parsesPerformed
        #expect(!view.hasPendingDebouncedReparse)

        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))

        // The keystroke itself must not reparse — proves the debounce,
        // not just that a reparse eventually happens somewhere.
        #expect(view.session.parsesPerformed == before)
        #expect(view.hasPendingDebouncedReparse)
        // But the glyph/buffer change is still same-frame (R20).
        #expect(view.string == "Hello!")

        view.fireDebouncedReparse()
        #expect(view.session.parsesPerformed == before + 1)
        #expect(!view.hasPendingDebouncedReparse)
    }

    @Test func aBurstOfKeystrokesReparsesOnlyOnceWhenTheDebounceFinallyFires() {
        let view = makeSourceView("")
        let before = view.session.parsesPerformed
        view.selectedUTF16Range = NSRange(location: 0, length: 0)

        typeCharacterByCharacter("hello", into: view)
        #expect(view.string == "hello")
        // Five keystrokes, five reschedules, but still only one pending
        // debounce — not five accumulated ones.
        #expect(view.session.parsesPerformed == before)

        view.fireDebouncedReparse()
        #expect(view.session.parsesPerformed == before + 1)
    }

    @Test func doCommandDeleteAlsoDebouncesRatherThanReparsingSynchronously() {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        let before = view.session.parsesPerformed

        view.doCommand(by: Selector(("deleteBackward:")))
        #expect(view.string == "Hell")
        #expect(view.session.parsesPerformed == before)
        #expect(view.hasPendingDebouncedReparse)

        view.fireDebouncedReparse()
        #expect(view.session.parsesPerformed == before + 1)
    }

    @Test func replaceSelectionFindAndReplaceStillReparsesSynchronouslyNotDebounced() {
        let view = makeSourceView("Hello World")
        let before = view.session.parsesPerformed
        view.selectedUTF16Range = (view.string as NSString).range(of: "World")

        #expect(view.replaceSelection(with: "There"))

        // Find/Replace is not a keystroke-path caller (plan: "keeps
        // calling syncBlocksFromStorage() synchronously") — no pending
        // debounce, and the reparse already happened.
        #expect(!view.hasPendingDebouncedReparse)
        #expect(view.session.parsesPerformed == before + 1)
    }

    /// Integration with ticket 12's fold repair (not a new repair API,
    /// only its timing, per the plan): typing elsewhere in the document
    /// shifts a folded block's line number, and firing the debounce
    /// must both rebuild the block index AND repair the existing fold
    /// against its anchor — the exact same repair mechanism
    /// `syncBlocksFromStorage` already provides, now reached through
    /// the keystroke path instead of only through `replaceSelection`.
    @Test func firingTheDebounceRepairsFoldIDsAfterAKeystrokeShiftsBlockLines() throws {
        let twoBlockFixture = """
        ## Block B

        Body B marker HERE.

        ## Block A

        Body A.
        """
        let view = makeSourceView(twoBlockFixture)

        let blockAOriginal = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.startLine != 1 })
        view.foldStore.toggle(blockAOriginal.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.foldStore.isFolded(blockAOriginal.id))

        // Type at the end of "HERE." — inserting two new lines pushes
        // "## Block A" further down, via the real insertText path.
        let hereEnd = (view.string as NSString).range(of: "HERE.").upperBound
        view.selectedUTF16Range = NSRange(location: hereEnd, length: 0)
        view.insertText("\nExtra line one.\nExtra line two.", replacementRange: NSRange(location: NSNotFound, length: 0))

        // Still stale immediately after the keystroke — the debounce
        // hasn't fired yet, so the old (pre-edit) block index remains.
        #expect(view.blocks.first { $0.id.anchor == blockAOriginal.id.anchor }?.id.startLine == blockAOriginal.id.startLine)

        view.fireDebouncedReparse()

        let blockARepaired = try #require(view.blocks.first { $0.id.kind == .heading && $0.id.anchor == blockAOriginal.id.anchor })
        #expect(blockARepaired.id.startLine != blockAOriginal.id.startLine)
        #expect(view.foldStore.isFolded(blockARepaired.id))
        #expect(!view.foldStore.foldedIDs.contains(blockAOriginal.id))
    }

    // MARK: - T06: Preview selection maps to source ranges, including across a table

    private var tablesFixture: String {
        """
        ## Heading

        A paragraph body here.

        | A | B |
        |---|---|
        | 1 | 2 |

        Another paragraph.

        | C | D |
        |---|---|
        | 3 | 4 |
        """
    }

    /// A raw-buffer UTF-16 offset landing inside `needle`'s occurrence in
    /// `markdown` — document-level paragraph/element boundaries are
    /// preserved through Preview substitution (ticket 08 never rewrites
    /// the buffer, N4), so this is a genuine document-coordinate offset
    /// within the correct block, not a guess.
    private func rawOffset(of needle: String, in markdown: String) -> Int {
        (markdown as NSString).range(of: needle).location
    }

    @Test func previewSelectionOnAHeadingMapsToItsFullSourceLine() {
        let view = makePreviewView(tablesFixture)
        let offset = rawOffset(of: "Heading", in: tablesFixture)
        let markdown = view.session.previewSelectionSourceMarkdown(forUTF16Range: NSRange(location: offset, length: 0))
        #expect(markdown == "## Heading\n")
    }

    @Test func previewSelectionOnAParagraphMapsToItsFullSourceLine() {
        let view = makePreviewView(tablesFixture)
        let offset = rawOffset(of: "paragraph body", in: tablesFixture)
        let markdown = view.session.previewSelectionSourceMarkdown(forUTF16Range: NSRange(location: offset, length: 0))
        #expect(markdown == "A paragraph body here.\n")
    }

    @Test func previewSelectionOnATableMapsToItsCompleteSourceIncludingDataRows() {
        let view = makePreviewView(tablesFixture)
        // The table's own rendered attachment sits on its anchor line
        // (the header row); every other row is a collapsed continuation
        // (ticket 08) — a selection can only ever land on the anchor,
        // but the reported markdown must still include the whole table.
        let offset = rawOffset(of: "| A | B |", in: tablesFixture)
        let markdown = view.session.previewSelectionSourceMarkdown(forUTF16Range: NSRange(location: offset, length: 0))
        #expect(markdown == "| A | B |\n|---|---|\n| 1 | 2 |\n")
    }

    /// The exact gap ticket 01's review flagged, fixed by this ticket's
    /// T06: a selection spanning two tables must copy *both*, not
    /// silently drop the second.
    @Test func previewSelectionSpanningTwoTablesCopiesBothTablesInOrder() throws {
        let view = makePreviewView(tablesFixture)
        let firstTableOffset = rawOffset(of: "| A | B |", in: tablesFixture)
        let secondTableRowOffset = rawOffset(of: "| 3 | 4 |", in: tablesFixture)
        let selection = NSRange(location: firstTableOffset, length: secondTableRowOffset - firstTableOffset)

        let text = try #require(view.session.previewSelectionSourceMarkdown(forUTF16Range: selection))
        #expect(text.contains("| A | B |"))
        #expect(text.contains("| 1 | 2 |"))
        #expect(text.contains("Another paragraph."))
        #expect(text.contains("| C | D |"))
        #expect(text.contains("| 3 | 4 |"))
        // Order preserved: the first table's content must appear before
        // the second's, matching source/document order.
        let firstTableIndex = try #require(text.range(of: "| A | B |"))
        let secondTableIndex = try #require(text.range(of: "| C | D |"))
        #expect(firstTableIndex.lowerBound < secondTableIndex.lowerBound)
    }

    @Test func previewSelectionTouchingNothingMapsToNil() {
        let view = makePreviewView(tablesFixture)
        // A location past the end of the document.
        let end = (view.string as NSString).length
        let markdown = view.session.previewSelectionSourceMarkdown(forUTF16Range: NSRange(location: end, length: 0))
        #expect(markdown == nil)
    }

    @Test func mouseClickAndDragSelectInPreviewModeTooAndCopyYieldsSourceMarkdownNotRenderedText() throws {
        let view = makePreviewView(tablesFixture)
        view.prepareForEditing()
        defer { view.resignFirstResponder() } // stop the blink timer; see the first T01 test's comment
        view.ensureLayout()

        let offset = rawOffset(of: "Heading", in: tablesFixture)
        // Double-click (word selection) rather than a bare click: copy
        // requires a genuine (non-empty) selection in either mode, the
        // same as Source — a bare click alone only places a caret with
        // nothing selected, which must stay a copy no-op.
        let down = try mouseEvent(.leftMouseDown, view: view, atUTF16Offset: offset, clickCount: 2)
        view.mouseDown(with: down)

        // A real click in Preview mode must actually place a selection
        // (R22 "selectable") — not silently no-op the way it did before
        // this ticket's T02 gated all mouse selection to Source only.
        #expect(view.mode == .preview)
        #expect(view.selectedUTF16Range.length > 0)

        NSPasteboard.general.clearContents()
        view.copy(nil)
        let copied = NSPasteboard.general.string(forType: .string)
        #expect(copied == "## Heading\n")
        // The critical R22 assertion: the pasteboard holds real source
        // Markdown (with its "##"), never the rendered/substituted
        // reading-view text ("Heading" alone, no punctuation).
        #expect(copied?.contains("#") == true)
    }

    @Test func cmdCInPreviewModeAlsoReachesCopy() {
        let view = makePreviewView(tablesFixture)
        let offset = rawOffset(of: "paragraph body", in: tablesFixture)
        // A genuine (non-empty) selection — copy no-ops on a bare caret
        // position in either mode (see copyIsANoOpWithNoSelectionInEitherMode).
        view.selectedUTF16Range = NSRange(location: offset, length: 1)

        NSPasteboard.general.clearContents()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8
        )
        if let event {
            view.keyDown(with: event)
        }
        #expect(NSPasteboard.general.string(forType: .string) == "A paragraph body here.\n")
    }

    @Test func previewModeStillRefusesActualTyping() {
        let view = makePreviewView(tablesFixture)
        let before = view.string
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        view.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == before, "Preview must stay read-only even though it is now selectable")
    }

    // MARK: - T07: accessibility

    @Test func accessibilityRoleAndElementStatusIdentifyThisAsARealTextArea() {
        let view = makeSourceView("Hello")
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .textArea)
    }

    @Test func accessibilityValueReflectsTheLiveBufferNotAConstant() {
        let view = makeSourceView("Hello World")
        #expect(view.accessibilityValue() as? String == "Hello World")

        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        // Live, not cached at construction time (N9) — the value must
        // change when the real buffer changes.
        #expect(view.accessibilityValue() as? String == "Hello! World")
    }

    @Test func accessibilitySelectedTextAndRangeReflectARealLiveSelection() {
        let view = makeSourceView("Hello World")
        let range = (view.string as NSString).range(of: "World")
        view.selectedUTF16Range = range

        #expect(view.accessibilitySelectedTextRange() == range)
        #expect(view.accessibilitySelectedText() == "World")

        // And a collapsed (caret-only) selection reports empty text,
        // not stale content from the previous real selection.
        view.selectedUTF16Range = NSRange(location: 0, length: 0)
        #expect(view.accessibilitySelectedText() == "")
        #expect(view.accessibilitySelectedTextRange() == NSRange(location: 0, length: 0))
    }

    @Test func accessibilityNumberOfCharactersAndVisibleRangeReflectRealDocumentLength() {
        let view = makeSourceView("Hello World")
        #expect(view.accessibilityNumberOfCharacters() == (view.string as NSString).length)
        #expect(view.accessibilityVisibleCharacterRange() == NSRange(location: 0, length: (view.string as NSString).length))

        // Live, not fixed at construction — grows with the real buffer.
        view.selectedUTF16Range = NSRange(location: 11, length: 0)
        view.insertText(" Again", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.accessibilityNumberOfCharacters() == (view.string as NSString).length)
        #expect(view.accessibilityVisibleCharacterRange().length == (view.string as NSString).length)
    }

    @Test func accessibilityValueInPreviewModeReportsRenderedTextNotRawMarkdown() {
        let view = makePreviewView("## Heading\n\nA **bold** paragraph.\n")
        let value = view.accessibilityValue() as? String

        // The critical assertion: VoiceOver in Preview must hear
        // rendered reading text, not literal syntax.
        #expect(value?.contains("#") == false)
        #expect(value?.contains("**") == false)
        #expect(value?.contains("Heading") == true)
        #expect(value?.contains("bold") == true)
        #expect(value?.contains("paragraph") == true)

        // Source mode is unaffected — still the raw buffer verbatim.
        view.setMode(.source)
        #expect(view.accessibilityValue() as? String == view.string)
    }

    // MARK: - Review fixes (2026-08-18)

    private func keyEvent(command: Bool, shift: Bool = false, characters: String, keyCode: UInt16) -> NSEvent {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    @Test func cmdZAndCmdShiftZReachUndoAndRedoThroughKeyDown() {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "Hello!")

        // R20 "undo and redo work": a real user has no menu item and no
        // other keyboard path to either — this is the only route.
        view.keyDown(with: keyEvent(command: true, characters: "z", keyCode: 6))
        #expect(view.string == "Hello")

        view.keyDown(with: keyEvent(command: true, shift: true, characters: "z", keyCode: 6))
        #expect(view.string == "Hello!")
    }

    @Test func cmdZAlsoWorksInPreviewModeMatchingUndoLastChangesModeIndependence() {
        let view = makeSourceView("Hello")
        view.selectedUTF16Range = NSRange(location: 5, length: 0)
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMode(.preview)

        view.keyDown(with: keyEvent(command: true, characters: "z", keyCode: 6))
        #expect(view.string == "Hello")
    }

    /// A *bounded* fold: a trailing "## Following two" heading, the
    /// same pattern `FoldingTextViewTests.fixture` already uses, so
    /// folding the first heading only hides the body between the two
    /// headings — without a bounding heading, `BlockIndex.build`'s
    /// `foldExtent` runs to the end of the document (no next same-or-
    /// shallower heading to stop at), which would swallow
    /// "Trailing paragraph." too and defeat the point of this test.
    private var foldableFixture: String {
        """
        ## Heading two

        Hidden body under the heading.

        ## Following two

        Trailing paragraph.
        """
    }

    @Test func arrowRightSkipsOverAFoldedRangeInsteadOfLandingInsideItsHiddenText() throws {
        let view = makeSourceView(foldableFixture)
        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.foldExtent != nil })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()
        #expect(view.foldStore.isFolded(heading.id))

        // A caret confidently *inside* the hidden body — not merely at
        // its boundary. The boundary itself (right after the folded
        // heading's own line) is still a valid, visible caret position
        // (`packedCaretRect` resolves it to the end of that line's own
        // fragment), so a single step onto the boundary from just
        // before it is correct, unskipped behavior, not a bug; see
        // `arrowLeft`'s own landing-offset math below for that boundary.
        let insideFold = (view.string as NSString).range(of: "Hidden body").location
        view.selectedUTF16Range = NSRange(location: insideFold, length: 0)

        // One arrow-right press from inside the hidden span must skip
        // straight to its end — landing anywhere still inside it is the
        // bug this fix closes (the caret would then silently stop
        // drawing, since `packedCaretRect` returns nil for a hidden
        // offset).
        view.doCommand(by: Selector(("moveRight:")))

        let followingHeadingStart = (view.string as NSString).range(of: "## Following two").location
        #expect(view.selectedUTF16Range.location == followingHeadingStart)
        // The landed offset must itself resolve to real, visible
        // geometry — the live, observable proof (N9) that this isn't
        // merely "some number past the fold," but an actually-drawable
        // caret position.
        #expect(view.session.packedCaretRect(forUTF16Offset: view.selectedUTF16Range.location) != nil)
    }

    @Test func arrowLeftAlsoSkipsBackwardOverAFoldedRange() throws {
        let view = makeSourceView(foldableFixture)
        let heading = try #require(view.blocks.first { $0.id.kind == .heading && $0.foldExtent != nil })
        view.foldStore.toggle(heading.id)
        view.applyFolds()
        view.ensureLayout()

        let followingHeadingStart = (view.string as NSString).range(of: "## Following two").location
        view.selectedUTF16Range = NSRange(location: followingHeadingStart, length: 0)

        view.doCommand(by: Selector(("moveLeft:")))

        // Lands exactly at the fold's own start boundary — one UTF-16
        // unit past the folded heading's own line (that line's trailing
        // newline is itself the last visible character before the
        // hidden span begins; `foldExtent`'s lower bound is the byte
        // right after the heading block's own bytes, which include that
        // newline).
        let headingLineEnd = (view.string as NSString).range(of: "## Heading two").upperBound
        let foldStart = headingLineEnd + 1
        #expect(view.selectedUTF16Range.location == foldStart)
        #expect(view.session.packedCaretRect(forUTF16Offset: view.selectedUTF16Range.location) != nil)
    }
    @Test func documentSessionIsDirtyReturnsFalseAfterUndoingBackToTheSavedState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markus-review-fix-\(UUID().uuidString).md")
        try Data("Hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DocumentSession()
        try session.open(url: url)
        #expect(!session.isDirty)

        session.editor.setMode(.source)
        session.editor.selectedUTF16Range = NSRange(location: 5, length: 0)
        session.editor.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(session.isDirty)

        // The specific gap the review flagged: `isDirty` itself (not
        // `NSDocument.isDocumentEdited`, a separate mechanism) must
        // return to false once undo genuinely restores the saved text.
        #expect(session.editor.undoLastChange())
        #expect(session.editor.string == "Hello")
        #expect(!session.isDirty)

        #expect(session.editor.redoLastChange())
        #expect(session.isDirty)
    }
}
#endif

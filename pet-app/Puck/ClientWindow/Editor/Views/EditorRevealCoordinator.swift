//
//  EditorRevealCoordinator.swift
//  Puck
//
//  Applies EditorPaneStore.RevealRequest to the live text view: select the
//  line range, scroll it into view.
//
//  Not through SourceEditorState.cursorPositions, which is the obvious route
//  and does not work. SourceEditor only reads that binding when it first
//  makes the controller; its update path compares state.cursorPositions
//  against itself (SourceEditor.swift, 0.15.2), so nothing set afterwards
//  ever reaches the text view. A TextViewCoordinator hands over the
//  controller itself, which also gets us scroll-to-visible -- something the
//  state route never offered.
//

import AppKit
import CodeEditSourceEditor

final class EditorRevealCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    /// Held until there is a text view to apply it to. A tour normally
    /// reveals a file that is not open yet, so the request arrives while
    /// that tab's editor is still being built.
    private var pending: ClosedRange<Int>?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        flush()
    }

    func controllerDidAppear(controller: TextViewController) {
        self.controller = controller
        flush()
    }

    func destroy() {
        controller = nil
    }

    func reveal(lines: ClosedRange<Int>) {
        pending = lines
        flush()
    }

    private func flush() {
        guard let lines = pending, lines.lowerBound >= 1,
              let controller,
              let layoutManager = controller.textView?.layoutManager,
              let first = layoutManager.textLineForIndex(lines.lowerBound - 1)
        else {
            return
        }
        pending = nil
        // A range past the end of the file selects to the last line rather
        // than nothing: the caption is still about roughly there, and a
        // silent no-op would leave the pet pointing at an unchanged screen.
        let last = layoutManager.textLineForIndex(lines.upperBound - 1) ?? first
        // An explicit NSRange rather than line/column: setCursorPositions'
        // own column arithmetic clamps a column against an absolute offset,
        // and offsets we compute here skip that entirely.
        controller.setCursorPositions(
            [CursorPosition(range: NSRange(
                location: first.range.lowerBound,
                length: max(0, last.range.upperBound - first.range.lowerBound)
            ))],
            scrollToVisible: true
        )
    }
}

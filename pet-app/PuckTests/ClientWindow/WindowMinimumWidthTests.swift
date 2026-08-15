//
//  WindowMinimumWidthTests.swift
//  PuckTests
//
//  The window's floor has to be at least what the panes inside it declare.
//  It wasn't: the editor pane needed 540 while the window allowed 960 total
//  against a chat that wanted 480, and the missing 60+ came out of the file
//  tree, whose rows were clipped instead of truncated.
//
//  These numbers are duplicated from the view layer on purpose -- that is the
//  point. If someone widens a pane's minimum without revisiting the window's,
//  the arithmetic here stops adding up and says so.
//

import XCTest
@testable import Puck

final class WindowMinimumWidthTests: XCTestCase {
    /// What ClientWindowView gives ChatPaneView.
    private let chatPaneMinimum: CGFloat = 560
    /// What ClientWindowView gives EditorPaneView.
    private let editorPaneMinimum: CGFloat = 540
    /// EditorPaneView's own HSplitView: file tree + code column.
    private let fileTreeMinimum: CGFloat = 180
    private let codeColumnMinimum: CGFloat = 360

    func testTheEditorPanesFloorCoversWhatIsInsideIt() {
        // The original defect in one assertion: EditorPaneView declared 360
        // while its own two columns needed 540 between them, so the pane
        // could be handed less width than it could actually draw.
        XCTAssertGreaterThanOrEqual(editorPaneMinimum, fileTreeMinimum + codeColumnMinimum)
    }

    func testTheEditorWindowFloorFitsBothPanes() {
        XCTAssertGreaterThanOrEqual(
            ClientTheme.Metrics.windowMinWidthWithEditor,
            chatPaneMinimum + editorPaneMinimum,
            "a window that cannot fit both panes squeezes one of them below its own minimum"
        )
    }

    func testTheChatOnlyFloorFitsTheChat() {
        XCTAssertGreaterThanOrEqual(ClientTheme.Metrics.windowMinWidth, chatPaneMinimum)
    }

    func testOpeningTheEditorRaisesTheFloorRatherThanSharingOne() {
        // One number for both modes is what forced the compromise: generous
        // for a chat, short for a chat plus an editor.
        XCTAssertGreaterThan(
            ClientTheme.Metrics.windowMinWidthWithEditor,
            ClientTheme.Metrics.windowMinWidth
        )
    }

    func testTheFloorsAreNotAbsurdlyLargeForATypicalDisplay() {
        // A floor wider than a small laptop's screen is unusable, not safe.
        // 1280 is the narrowest built-in display Apple currently ships.
        XCTAssertLessThanOrEqual(ClientTheme.Metrics.windowMinWidthWithEditor, 1280)
    }
}

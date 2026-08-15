//
//  EditorPresentationTests.swift
//  PuckTests
//
//  Three states rather than a Bool (2026-08-16): "closed" and "open in its own
//  window" are different answers to every question the chat window asks --
//  whether to split, how wide it must be, what the toolbar says. The
//  transitions are where that distinction either holds or collapses back into
//  a Bool, so they are what these cover.
//

import XCTest
@testable import Puck

final class EditorPresentationTests: XCTestCase {
    func testTheToggleOpensAndClosesTheSplit() {
        XCTAssertEqual(EditorPresentation.hidden.toggled, .attached)
        XCTAssertEqual(EditorPresentation.attached.toggled, .hidden)
    }

    func testTheToggleLeavesADetachedEditorWhereItIs() {
        // Yanking it back into the split would fight the user who just moved
        // it out; closing that window is how it comes back.
        XCTAssertEqual(EditorPresentation.detached.toggled, .detached)
    }

    func testOnlyTheSplitCountsAsAttached() {
        XCTAssertTrue(EditorPresentation.attached.isAttached)
        XCTAssertFalse(EditorPresentation.detached.isAttached)
        XCTAssertFalse(EditorPresentation.hidden.isAttached)
    }

    func testDetachedStillCountsAsVisible() {
        // The file is on screen, so a reveal request has nothing to do -- this
        // is what stops it dragging the editor back into the split.
        XCTAssertTrue(EditorPresentation.detached.isVisible)
        XCTAssertTrue(EditorPresentation.attached.isVisible)
        XCTAssertFalse(EditorPresentation.hidden.isVisible)
    }

    func testOnlyTheSplitRaisesTheWindowFloor() {
        // Detached, the chat window is a chat window again -- the wider floor
        // exists for two panes sharing one window.
        XCTAssertGreaterThan(
            ClientTheme.Metrics.windowMinWidthWithEditor,
            ClientTheme.Metrics.windowMinWidth
        )
        // The split's floor is both panes plus the divider between them, so
        // the detached editor's own floor is what is left after the chat's
        // share and that allowance -- not a plain subtraction.
        let splitterAllowance = ClientTheme.Metrics.windowMinWidthWithEditor
            - ClientTheme.Metrics.windowMinWidth
            - ClientTheme.Metrics.editorWindowMinWidth
        XCTAssertEqual(splitterAllowance, 20, "the split reserves a divider's width the detached window doesn't need")
        XCTAssertLessThan(
            ClientTheme.Metrics.editorWindowMinWidth,
            ClientTheme.Metrics.windowMinWidthWithEditor,
            "a window showing only the editor cannot need more than one showing both"
        )
    }
}

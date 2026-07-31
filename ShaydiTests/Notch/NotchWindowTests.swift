//
//  NotchWindowTests.swift
//  Shaydi
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  Verifies the declared window configuration -- unlike OverlayWindow, this
//  one does accept mouse events (the toy buttons need to be clickable), but
//  it must still never become key/main.
//

import XCTest
import AppKit
@testable import Shaydi

final class NotchWindowTests: XCTestCase {
    private func makeWindow() -> NotchWindow {
        NotchWindow(contentRect: CGRect(x: 0, y: 0, width: 160, height: 24))
    }

    func test_isBorderlessAndTransparent() {
        let window = makeWindow()

        XCTAssertEqual(window.styleMask, [.borderless])
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func test_floatsAboveNormalWindowsAndJoinsAllSpaces() {
        let window = makeWindow()

        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func test_acceptsMouseEvents_unlikeOverlayWindow() {
        // OverlayWindow.ignoresMouseEvents defaults true (click-through) --
        // this window hosts real buttons, so it must not.
        XCTAssertFalse(makeWindow().ignoresMouseEvents)
    }

    func test_neverBecomesKeyOrMain() {
        let window = makeWindow()

        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
    }
}

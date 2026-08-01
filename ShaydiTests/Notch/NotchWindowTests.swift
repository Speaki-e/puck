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

    // .statusBar, not .floating -- byeolki, 2026-08-01: the real notch sits
    // AT the menu bar's own stripe, not merely above ordinary app windows.
    // .statusBar is the level NSStatusItem/menu extras themselves use.
    func test_floatsAtStatusBarLevelAndJoinsAllSpaces() {
        let window = makeWindow()

        XCTAssertEqual(window.level, .statusBar)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    // 2026-08-01: an NSWindow-level shadow draws a rectangular penumbra
    // behind NotchShape's flare, reading as a floating pill instead of an
    // extension of the menu bar -- NotchView draws its own conditional
    // shadow only while expanded instead (see NotchViewTests-adjacent
    // reasoning in NotchView's doc comment).
    func test_hasNoWindowLevelShadow() {
        XCTAssertFalse(makeWindow().hasShadow)
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

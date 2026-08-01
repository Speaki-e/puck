//
//  ClientWindowTests.swift
//  Shaydi
//
//  F13 test · owner: 박해영 (Haeyoung Park)
//  Never orders the window on screen, so it doesn't visibly flash during
//  tests.
//

import XCTest
import AppKit
@testable import Shaydi

final class ClientWindowTests: XCTestCase {
    private func makeWindow() -> ClientWindow {
        ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 740))
    }

    // byeolki, 2026-08-02: "신호등만 색이 다르게 보임 ... 신호등 부분만
    // 다른 부분 같음" -- titlebarAppearsTransparent alone hides the gray
    // titlebar bar, but the window's own opaque default background still
    // shows through right around the traffic lights unless the window
    // itself is non-opaque with a clear background too.
    func test_isNonOpaqueWithClearBackground() {
        let window = makeWindow()

        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func test_appliesGlassChrome() {
        let window = makeWindow()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
    }

    func test_isReleasedWhenClosed_isFalse() {
        // A window cached in a strong property (AppDelegate.window) that IS
        // released on close is a use-after-free the next time it's shown --
        // a documented gap this repo has hit before with other windows.
        XCTAssertFalse(makeWindow().isReleasedWhenClosed)
    }
}

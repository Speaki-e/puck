//
//  TextInputBubbleWindowTests.swift
//  PetAgent
//
//  F6 test · owner: 박해영 (Haeyoung Park)
//  Verifies this is the one overlay-adjacent window that CAN become key.
//

import XCTest
import AppKit
@testable import PetAgent

final class TextInputBubbleWindowTests: XCTestCase {
    private func makeWindow() -> TextInputBubbleWindow {
        TextInputBubbleWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 60))
    }

    func test_canBecomeKey_unlikeOverlayWindow() {
        XCTAssertTrue(makeWindow().canBecomeKey)
    }

    func test_isBorderlessAndTransparentBackground() {
        let window = makeWindow()
        XCTAssertEqual(window.styleMask, [.borderless])
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func test_floatsAboveNormalWindows() {
        XCTAssertEqual(makeWindow().level, .floating)
    }
}

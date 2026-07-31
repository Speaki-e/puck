//
//  NotchWindowControllerTests.swift
//  Shaydi
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  screenFrameProvider is injectable for the same reason
//  TextInputBubbleWindow injects frontmostAppProvider -- a real NSScreen
//  can't be relied on to have a known frame inside a test runner.
//

import XCTest
import AppKit
@testable import Shaydi

final class NotchWindowControllerTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeController() -> NotchWindowController {
        let controller = NotchWindowController()
        controller.screenFrameProvider = { [screenFrame] in screenFrame }
        return controller
    }

    // byeolki, 2026-08-01: "맥북 노치가 메뉴막대 쪽에 있는데, 너가 만든거
    // 위치는 걍 메뉴막대를 제외한 화면 맨 위임" -- the real notch sits AT the
    // menu bar, not below it. The provider must default to NSScreen.frame
    // (the true screen bounds), never .visibleFrame (which excludes the
    // menu bar and would leave the pill floating under it instead of
    // overlapping the same stripe a real notch/menu bar occupies).
    func test_defaultScreenFrameProvider_usesFullScreenFrame_notVisibleFrame() {
        guard let screen = NSScreen.main else { return }
        let controller = NotchWindowController()

        XCTAssertEqual(controller.screenFrameProvider(), screen.frame)
    }

    func test_start_positionsWindow_topCenterOfScreen_atCollapsedSize() {
        let controller = makeController()

        controller.start(contentView: NSView())
        defer { controller.stop() }

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: NotchWindowController.collapsedSize
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_setExpanded_true_resizesToExpandedSize_keepingTopEdgeFixed() {
        let controller = makeController()
        controller.start(contentView: NSView())
        defer { controller.stop() }

        controller.setExpanded(true)

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: NotchWindowController.expandedSize
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_setExpanded_falseAfterTrue_returnsToCollapsedSize() {
        let controller = makeController()
        controller.start(contentView: NSView())
        defer { controller.stop() }

        controller.setExpanded(true)
        controller.setExpanded(false)

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: NotchWindowController.collapsedSize
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_stop_ordersOutAndClearsWindow() {
        let controller = makeController()
        controller.start(contentView: NSView())

        controller.stop()

        XCTAssertNil(controller.window)
    }
}

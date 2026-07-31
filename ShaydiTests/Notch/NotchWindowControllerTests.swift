//
//  NotchWindowControllerTests.swift
//  Shaydi
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  screenVisibleFrameProvider is injectable for the same reason
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
        controller.screenVisibleFrameProvider = { [screenFrame] in screenFrame }
        return controller
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

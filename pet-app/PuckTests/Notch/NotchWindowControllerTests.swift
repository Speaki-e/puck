//
//  NotchWindowControllerTests.swift
//  Puck
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  screenFrameProvider/screenMetricsProvider are injectable for the same
//  reason TextInputBubbleWindow injects frontmostAppProvider -- a real
//  NSScreen can't be relied on to have a known frame/notch inside a test
//  runner.
//

import XCTest
import AppKit
@testable import Puck

final class NotchWindowControllerTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    // A real MacBook Pro 14"-shaped notch, in points.
    private let notchMetrics = NotchScreenMetrics(
        screenWidth: 1728, notchHeight: 32,
        auxiliaryLeftWidth: 190, auxiliaryRightWidth: 190, menuBarHeight: 24
    )

    private func makeController(metrics: NotchScreenMetrics? = nil) -> NotchWindowController {
        let controller = NotchWindowController()
        controller.screenFrameProvider = { [screenFrame] in screenFrame }
        controller.screenMetricsProvider = { metrics }
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

    // 2026-08-01: after cloning boring.notch's source to fix the notch
    // sizing, the default provider must read the same NSScreen values
    // boring.notch's getClosedNotchSize does -- not a hardcoded guess.
    func test_defaultScreenMetricsProvider_matchesLiveScreenValues() {
        guard let screen = NSScreen.main else { return }
        let controller = NotchWindowController()

        let metrics = controller.screenMetricsProvider()

        XCTAssertEqual(metrics?.screenWidth, screen.frame.width)
        XCTAssertEqual(metrics?.notchHeight, screen.safeAreaInsets.top)
        XCTAssertEqual(metrics?.auxiliaryLeftWidth, screen.auxiliaryTopLeftArea?.width)
        XCTAssertEqual(metrics?.auxiliaryRightWidth, screen.auxiliaryTopRightArea?.width)
    }

    func test_start_positionsWindow_topCenterOfScreen_atCollapsedSize() {
        let controller = makeController(metrics: notchMetrics)

        controller.start(contentView: NSView())
        defer { controller.stop() }

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY,
            size: NotchGeometry.closedSize(for: notchMetrics)
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_start_withNoNotchMetricsAvailable_fallsBackToFallbackSize() {
        let controller = makeController(metrics: nil)

        controller.start(contentView: NSView())
        defer { controller.stop() }

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: NotchGeometry.fallbackSize
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_setExpanded_true_resizesToExpandedSize_keepingTopEdgeFixed() {
        let controller = makeController(metrics: notchMetrics)
        controller.start(contentView: NSView())
        defer { controller.stop() }

        controller.setExpanded(true)

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: NotchWindowController.expandedSize
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_setExpanded_falseAfterTrue_returnsToCollapsedSize() {
        let controller = makeController(metrics: notchMetrics)
        controller.start(contentView: NSView())
        defer { controller.stop() }

        controller.setExpanded(true)
        controller.setExpanded(false)

        let expected = NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY,
            size: NotchGeometry.closedSize(for: notchMetrics)
        )
        XCTAssertEqual(controller.window?.frame, expected)
    }

    func test_stop_ordersOutAndClearsWindow() {
        let controller = makeController(metrics: notchMetrics)
        controller.start(contentView: NSView())

        controller.stop()

        XCTAssertNil(controller.window)
    }
}

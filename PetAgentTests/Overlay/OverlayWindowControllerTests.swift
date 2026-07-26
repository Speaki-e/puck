//
//  OverlayWindowControllerTests.swift
//  PetAgent
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  Verifies one window is created per real display and positioned using
//  AppKit frames (not the normalized, Y-down movement-logic space).
//

import XCTest
@testable import PetAgent

final class OverlayWindowControllerTests: XCTestCase {
    func test_start_createsOneWindowPerDisplay_positionedAtItsAppKitFrame() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(controller.windows.count, screenManager.current.appKitFrames.count)
        for (window, frame) in zip(controller.windows, screenManager.current.appKitFrames) {
            XCTAssertEqual(window.frame, frame)
        }
    }

    func test_stop_ordersOutAndClearsWindows() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        controller.start()
        controller.stop()

        XCTAssertTrue(controller.windows.isEmpty)
    }
}

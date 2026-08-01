//
//  NotchGeometryTests.swift
//  Shaydi
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  Pure math, no live NSScreen needed -- mirrors how NotchLayoutTests
//  verifies placement without a real window.
//

import XCTest
import CoreGraphics
@testable import Shaydi

final class NotchGeometryTests: XCTestCase {
    func test_realNotch_widthComesFromAuxiliaryAreas_heightFromSafeAreaInset() {
        let metrics = NotchScreenMetrics(
            screenWidth: 1728, notchHeight: 32,
            auxiliaryLeftWidth: 190, auxiliaryRightWidth: 190, menuBarHeight: 24
        )

        let size = NotchGeometry.closedSize(for: metrics)

        // boring.notch's own "+4" fudge: the auxiliary areas alone come out
        // a few points narrower than the real notch renders.
        XCTAssertEqual(size.width, 1728 - 190 - 190 + 4)
        XCTAssertEqual(size.height, 32)
    }

    func test_realNotch_withoutAuxiliaryAreaData_fallsBackToFallbackWidth() {
        let metrics = NotchScreenMetrics(
            screenWidth: 1728, notchHeight: 32,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24
        )

        let size = NotchGeometry.closedSize(for: metrics)

        XCTAssertEqual(size, CGSize(width: NotchGeometry.fallbackSize.width, height: 32))
    }

    func test_nonNotchedScreen_heightFallsBackToMenuBarHeight() {
        let metrics = NotchScreenMetrics(
            screenWidth: 1920, notchHeight: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24
        )

        let size = NotchGeometry.closedSize(for: metrics)

        XCTAssertEqual(size, CGSize(width: NotchGeometry.fallbackSize.width, height: 24))
    }

    func test_nonNotchedScreen_withNoMenuBarHeightEither_usesFullFallbackSize() {
        let metrics = NotchScreenMetrics(
            screenWidth: 1920, notchHeight: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 0
        )

        let size = NotchGeometry.closedSize(for: metrics)

        XCTAssertEqual(size, NotchGeometry.fallbackSize)
    }

    func test_realNotch_ignoresMenuBarHeight_heightAlwaysComesFromNotchHeight() {
        let metrics = NotchScreenMetrics(
            screenWidth: 1728, notchHeight: 32,
            auxiliaryLeftWidth: 190, auxiliaryRightWidth: 190, menuBarHeight: 999
        )

        let size = NotchGeometry.closedSize(for: metrics)

        XCTAssertEqual(size.height, 32)
    }
}

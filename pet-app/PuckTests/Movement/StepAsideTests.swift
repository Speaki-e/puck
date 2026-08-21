//
//  StepAsideTests.swift
//  Puck
//
//  What the pet does when the surface underfoot goes *behind* a window
//  rather than away: the user clicked that window, and the pet -- which
//  draws above every window -- would otherwise drop into the middle of it
//  (2026-08-22).
//

import XCTest
import CoreGraphics
@testable import Puck

final class StepAsideTests: XCTestCase {
    private func window(_ frame: CGRect, id: CGWindowID) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 1, ownerName: nil, title: nil, layer: 0, frame: frame)
    }

    func test_coveringWindow_isTheFrontmostOneThePointFallsInside() {
        let front = window(CGRect(x: 0, y: 0, width: 500, height: 500), id: 1)
        let behind = window(CGRect(x: 0, y: 0, width: 800, height: 800), id: 2)

        XCTAssertEqual(WindowSupport.coveringWindow(at: CGPoint(x: 100, y: 100), in: [front, behind])?.windowID, 1)
        XCTAssertEqual(
            WindowSupport.coveringWindow(at: CGPoint(x: 600, y: 600), in: [front, behind])?.windowID,
            2,
            "outside the front one, still inside the one behind it"
        )
        XCTAssertNil(WindowSupport.coveringWindow(at: CGPoint(x: 900, y: 900), in: [front, behind]))
    }

    func test_asideTarget_isTheNearerSideOfTheWindow_onTheFloor() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let frame = CGRect(x: 300, y: 100, width: 400, height: 400)

        XCTAssertEqual(
            WindowSupport.asideTarget(from: CGPoint(x: 350, y: 100), avoiding: frame, in: area, petHalfWidth: 50),
            CGPoint(x: 250, y: 600)
        )
        XCTAssertEqual(
            WindowSupport.asideTarget(from: CGPoint(x: 650, y: 100), avoiding: frame, in: area, petHalfWidth: 50),
            CGPoint(x: 750, y: 600)
        )
    }

    /// The chat window is 15..1455 of a 1470-wide screen: neither side has
    /// room for a pet. Walking anyway would only pick a different spot inside
    /// the same window.
    func test_asideTarget_isNilWhenNeitherSideHasRoomForTheWholePet() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

        XCTAssertNil(WindowSupport.asideTarget(
            from: CGPoint(x: 500, y: 100),
            avoiding: CGRect(x: 10, y: 0, width: 980, height: 600),
            in: area,
            petHalfWidth: 50
        ))
    }
}

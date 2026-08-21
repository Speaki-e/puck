//
//  RoamPointTests.swift
//  Puck
//
//  Where a wander goes. Drawn as a distance from where the pet already is,
//  because a uniform draw over the whole width made nearly every wander a
//  full crossing -- the same trip, over and over (2026-08-22).
//

import XCTest
import CoreGraphics
@testable import Puck

final class RoamPointTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private var limits: ClosedRange<CGFloat> {
        let margin = area.width * AppDelegate.roamEdgeMargin
        return (area.minX + margin)...(area.maxX - margin)
    }

    func test_targetsStayInsideTheEdgeMargin() {
        for start in stride(from: CGFloat(0), through: 1000, by: 50) {
            for _ in 0..<50 {
                let point = AppDelegate.randomRoamPoint(in: area, from: start)
                XCTAssertTrue(limits.contains(point.x), "\(point.x) from \(start)")
                XCTAssertEqual(point.y, area.maxY, "wander targets are on the floor")
            }
        }
    }

    /// The point of the change: most draws are near, some are far. A uniform
    /// draw would put about half of them past a third of the screen.
    func test_mostWandersAreShortHops() {
        let start: CGFloat = 500
        let distances = (0..<400).map { _ in abs(AppDelegate.randomRoamPoint(in: area, from: start).x - start) }
        let short = distances.filter { $0 <= area.width * 0.3 }.count

        XCTAssertGreaterThan(short, 240, "at least ~60% short, by the 75/25 split")
        XCTAssertTrue(distances.contains { $0 > area.width * 0.3 }, "but not always short")
    }

    func test_thePetGoesBothWays() {
        let start: CGFloat = 500
        let points = (0..<200).map { _ in AppDelegate.randomRoamPoint(in: area, from: start).x }

        XCTAssertTrue(points.contains { $0 < start })
        XCTAssertTrue(points.contains { $0 > start })
    }

    /// A pet already pressed against the margin still gets somewhere to go --
    /// the draw is reflected back inwards rather than clamped onto the edge.
    func test_fromTheEdge_itMovesInwards() {
        let atEdge = limits.lowerBound
        let points = (0..<100).map { _ in AppDelegate.randomRoamPoint(in: area, from: atEdge).x }

        XCTAssertTrue(points.allSatisfy { $0 >= limits.lowerBound })
        XCTAssertTrue(points.contains { $0 > atEdge + 20 }, "it does not just sit on the margin")
    }

    func test_aZeroWidthAreaDoesNotCrash() {
        XCTAssertEqual(AppDelegate.randomRoamPoint(in: .zero, from: 0), .zero)
    }
}

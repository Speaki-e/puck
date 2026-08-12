//
//  NotchShapeTests.swift
//  Puck
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  What actually distinguishes this from a RoundedRectangle: the top
//  corners are cut away (concave), not rounded outward.
//

import XCTest
import SwiftUI
@testable import Puck

final class NotchShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 30)

    func test_animatableData_roundTripsBothRadii() {
        var shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)

        shape.animatableData = AnimatablePair(19, 24)

        XCTAssertEqual(shape.animatableData.first, 19)
        XCTAssertEqual(shape.animatableData.second, 24)
    }

    func test_path_staysWithinTheGivenRect() {
        let shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)

        let bounds = shape.path(in: rect).boundingRect

        XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
    }

    /// The distinguishing feature vs. RoundedRectangle: a top corner is cut
    /// away entirely, not rounded -- a point just inside the literal
    /// top-left pixel must fall outside the filled shape.
    func test_topCorners_areConcave_notRounded() {
        let shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        let path = shape.path(in: rect)

        XCTAssertFalse(path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 1)))
        XCTAssertFalse(path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 1)))
    }

    func test_center_isInsideTheShape() {
        let shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        let path = shape.path(in: rect)

        XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    func test_zeroRadii_degeneratesToAPlainRectangle() {
        let shape = NotchShape(topCornerRadius: 0, bottomCornerRadius: 0)
        let path = shape.path(in: rect)

        XCTAssertTrue(path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 1)))
    }
}

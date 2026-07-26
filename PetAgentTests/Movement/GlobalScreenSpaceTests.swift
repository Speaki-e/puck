//
//  GlobalScreenSpaceTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  Coordinate-space normalization (AppKit bottom-left origin <-> top-left,
//  Y-down normalized space) per plan/02_pet-app.md section 3.
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class GlobalScreenSpaceTests: XCTestCase {
    func test_singleScreen_normalizesTopLeftAndBottomLeft() {
        // AppKit: origin (0,0) is the screen's bottom-left, Y increases upward. One 1920x1080 screen.
        let space = GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        // AppKit bottom-left (0,0) -> normalized coordinate is the bottom of the screen (y = height)
        XCTAssertEqual(space.normalized(fromAppKit: CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 1080))
        // AppKit top-left (0,1080) -> normalized origin (0,0)
        XCTAssertEqual(space.normalized(fromAppKit: CGPoint(x: 0, y: 1080)), CGPoint(x: 0, y: 0))
    }

    func test_singleScreen_normalizedScreenFrameCoversWholeScreen() {
        let space = GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        XCTAssertEqual(space.normalizedScreenFrames, [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
        XCTAssertEqual(space.bounds, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func test_sideBySideDisplays_sameHeight_boundsSpanBoth() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: 1920, y: 0, width: 1920, height: 1080) // to the right of primary in AppKit
        let space = GlobalScreenSpace(appKitFrames: [primary, secondary])

        XCTAssertEqual(
            space.normalizedScreenFrames,
            [
                CGRect(x: 0, y: 0, width: 1920, height: 1080),
                CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            ]
        )
        XCTAssertEqual(space.bounds, CGRect(x: 0, y: 0, width: 3840, height: 1080))
    }

    func test_secondaryDisplayAbovePrimary_hasNegativeNormalizedY() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // AppKit y=1080 sits right above the primary screen's top edge -> physically "above" it
        let secondary = CGRect(x: 0, y: 1080, width: 1280, height: 800)
        let space = GlobalScreenSpace(appKitFrames: [primary, secondary])

        // In the normalized (Y-down) space, a screen physically "above" primary has negative Y
        XCTAssertEqual(space.normalizedScreenFrames[1], CGRect(x: 0, y: -800, width: 1280, height: 800))
    }

    func test_appKitPoint_isInverseOfNormalized() {
        let space = GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
        let original = CGPoint(x: 400, y: 300)

        let roundTripped = space.appKitPoint(fromNormalized: space.normalized(fromAppKit: original))

        XCTAssertEqual(roundTripped, original)
    }
}

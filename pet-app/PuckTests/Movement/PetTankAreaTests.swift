//
//  PetTankAreaTests.swift
//  Puck
//

import XCTest
import CoreGraphics
@testable import Puck

final class PetTankAreaTests: XCTestCase {
    private let overlayOrigin = CGPoint(x: 0, y: 0)
    private let overlaySize = CGSize(width: 1470, height: 956)
    private let pet = CGSize(width: 60, height: 72)

    func test_aTankOnThePrimaryDisplayBecomesAnOverlayLocalRect() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 1200, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 200, y: 39, width: 1200, height: 90))
    }

    /// The overlay window is not always at the origin of Quartz space -- on a
    /// second display it is not. The rect is rebased the same way the window
    /// list is (AppDelegate.overlayLocalWindows).
    func test_theRectIsRebasedOntoTheOverlayWindow() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 1670, y: 139, width: 800, height: 90),
            overlayOriginInQuartz: CGPoint(x: 1470, y: 100),
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 200, y: 39, width: 800, height: 90))
    }

    /// A tank the pet cannot stand in is not a tank. Refused rather than
    /// clamped: the pet stays on the desktop, which is somewhere it fits.
    func test_aTankTooSmallForThePetIsRefused() {
        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 100, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "narrower than two pets")

        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 1200, height: 40),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "shorter than the pet")
    }

    func test_aTankOutsideTheOverlayIsRefused() {
        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 3000, y: 39, width: 1200, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ))
    }
}

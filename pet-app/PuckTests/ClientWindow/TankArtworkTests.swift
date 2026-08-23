//
//  TankArtworkTests.swift
//  PuckTests
//
//  The one background that is a drawn picture rather than a gradient. A
//  missing resource is not a build error -- the lookup just returns nil and
//  the island falls back to its plain ground -- so it is checked here and in
//  scripts/check-resources.sh for the app bundles.
//

import XCTest
@testable import Puck

final class TankArtworkTests: XCTestCase {
    func test_theSeabedArtwork_isInTheBundle() throws {
        let name = try XCTUnwrap(TankBackground.seabed.islandArtworkName)

        XCTAssertNotNil(TankBackground.artwork(named: name))
    }

    /// Wide and shallow, because the island is a strip: an image anywhere
    /// near square would crop to a keyhole of itself at this height.
    func test_theSeabedArtwork_isWiderThanItIsTall() throws {
        let image = try XCTUnwrap(TankBackground.artwork(named: "seabed"))

        XCTAssertGreaterThan(image.size.width, image.size.height * 2)
    }

    func test_everyOtherBackground_isAGradient() {
        for background in TankBackground.allCases where background != .seabed {
            XCTAssertNil(background.islandArtworkName, "\(background) should not fill the island")
        }
    }

    /// Asked for on every frame the island draws.
    func test_artwork_isCached() throws {
        let first = try XCTUnwrap(TankBackground.artwork(named: "seabed"))
        let second = try XCTUnwrap(TankBackground.artwork(named: "seabed"))

        XCTAssertTrue(first === second)
    }

    func test_anUnknownName_isNil() {
        XCTAssertNil(TankBackground.artwork(named: "not-a-background"))
    }
}

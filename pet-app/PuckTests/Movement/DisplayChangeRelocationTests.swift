//
//  DisplayChangeRelocationTests.swift
//  PuckTests
//
//  The display changed under the pet. It has to end up somewhere it can be
//  seen, in an area that matches the screen it is now on.
//

import XCTest
@testable import Puck

final class DisplayChangeRelocationTests: XCTestCase {
    /// The pet's outline: 40 wide, 80 tall, standing on its own feet.
    private let visualBounds = CGRect(x: -20, y: -80, width: 40, height: 80)

    /// The reported bug. A 1080-tall display becomes a 900-tall one; the pet
    /// was standing on the old floor, which is now 180pt below anything drawn.
    func testAShorterScreenBringsThePetBackOntoIt() {
        let outcome = DisplayChangeRelocation.relocate(
            position: CGPoint(x: 600, y: 1080),
            visualBounds: visualBounds,
            desktop: CGRect(x: 0, y: 0, width: 1440, height: 900),
            tank: nil,
            isHome: false
        )

        XCTAssertEqual(outcome.roamableArea, CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(outcome.position.y, 900, "the pet stands on the new floor")
        XCTAssertEqual(outcome.position.x, 600, "and keeps the place it had")
        XCTAssertNil(outcome.desktopArea)
    }

    /// A narrower screen: the pet was near the old right edge, which is past
    /// the new one, and half of it would hang off.
    func testANarrowerScreenPullsThePetInByItsOwnOutline() {
        let outcome = DisplayChangeRelocation.relocate(
            position: CGPoint(x: 1900, y: 900),
            visualBounds: visualBounds,
            desktop: CGRect(x: 0, y: 0, width: 1440, height: 900),
            tank: nil,
            isHome: false
        )

        XCTAssertEqual(outcome.position.x, 1420, "the pet's right edge, not its feet, is what stops at 1440")
        XCTAssertEqual(outcome.position.y, 900)
    }

    /// An island shorter than the pet: there is nowhere it fits, and standing
    /// on the floor with its head out is better than hanging below it.
    func testAnAreaShorterThanThePetPutsItOnTheFloor() {
        let tank = CGRect(x: 200, y: 40, width: 800, height: 50)
        let outcome = DisplayChangeRelocation.relocate(
            position: CGPoint(x: 600, y: 400),
            visualBounds: visualBounds,
            desktop: CGRect(x: 0, y: 0, width: 1440, height: 900),
            tank: tank,
            isHome: true
        )

        XCTAssertEqual(outcome.position.y, tank.maxY)
    }

    /// Nothing to do: a pet already inside the new screen stays exactly where
    /// it is. A display change is not a reason to move it.
    func testAPetAlreadyOnScreenIsLeftAlone() {
        let outcome = DisplayChangeRelocation.relocate(
            position: CGPoint(x: 700, y: 500),
            visualBounds: visualBounds,
            desktop: CGRect(x: 0, y: 0, width: 1440, height: 900),
            tank: nil,
            isHome: false
        )

        XCTAssertEqual(outcome.position, CGPoint(x: 700, y: 500))
    }

    /// On the island, the island is still the room. Only the desktop it would
    /// come back to is re-measured -- left at the old screen's size, leaving
    /// the island would drop the pet off the bottom exactly as before.
    func testAPetOnTheIslandStaysOnItAndGetsANewDesktopToReturnTo() {
        let tank = CGRect(x: 200, y: 40, width: 800, height: 90)
        let outcome = DisplayChangeRelocation.relocate(
            position: CGPoint(x: 600, y: 130),
            visualBounds: visualBounds,
            desktop: CGRect(x: 0, y: 0, width: 1440, height: 900),
            tank: tank,
            isHome: true
        )

        XCTAssertEqual(outcome.roamableArea, tank)
        XCTAssertEqual(outcome.desktopArea, CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(outcome.position, CGPoint(x: 600, y: 130))
    }

    /// Home, but the client never reported a tank: there is no island to hold
    /// the pet, so the desktop is the only place left for it.
    func testHomeWithNoTankFallsBackToTheDesktop() {
        let outcome = DisplayChangeRelocation.relocate(
            position: CGPoint(x: 600, y: 1080),
            visualBounds: visualBounds,
            desktop: CGRect(x: 0, y: 0, width: 1440, height: 900),
            tank: nil,
            isHome: true
        )

        XCTAssertEqual(outcome.roamableArea, CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(outcome.position.y, 900)
        XCTAssertNil(outcome.desktopArea)
    }
}

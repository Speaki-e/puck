//
//  PetHomeDeciderTests.swift
//  Puck
//
//  The one place that decides whether the pet is in its tank. Kept pure so
//  the priority order and the debounce can be tested without a socket.
//

import XCTest
@testable import Puck

final class PetHomeDeciderTests: XCTestCase {
    private func settled(_ decider: PetHomeDecider) -> PetHomeDecider.Move? {
        // One second of frames at 60fps: past the 0.7s hold.
        var move: PetHomeDecider.Move?
        for _ in 0..<60 { move = decider.tick(dt: 1.0 / 60) ?? move }
        return move
    }

    func test_aVisibleTankOnAFrontmostWindow_bringsThePetHome() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true, pinned: false)

        XCTAssertEqual(settled(decider), .home)
    }

    /// The window going to the back is the ordinary way the pet leaves.
    func test_theWindowLosingFront_sendsThePetOut() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true, pinned: false)
        _ = settled(decider)

        decider.report(hasTank: true, visible: false, pinned: false)

        XCTAssertEqual(settled(decider), .desktop)
    }

    /// Alt-tabbing past the window should not teleport the pet twice.
    func test_aStateThatDoesNotHold_isNotActedOn() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true, pinned: false)

        var move: PetHomeDecider.Move?
        for _ in 0..<20 { move = decider.tick(dt: 1.0 / 60) ?? move } // ~0.33s
        XCTAssertNil(move, "not held long enough yet")

        decider.report(hasTank: true, visible: false, pinned: false)
        for _ in 0..<20 { move = decider.tick(dt: 1.0 / 60) ?? move }
        XCTAssertNil(move, "the new state has not held either")
    }

    func test_pinnedKeepsThePetHomeWhenTheWindowGoesBack() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true, pinned: true)
        XCTAssertEqual(settled(decider), .home)

        decider.report(hasTank: true, visible: false, pinned: true)

        XCTAssertNil(settled(decider), "still home; nothing to do")
    }

    /// A pet in a tank nobody can see is indistinguishable from a pet that
    /// has vanished, so this outranks the pin.
    func test_losingTheTankOutranksThePin() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true, pinned: true)
        _ = settled(decider)

        decider.report(hasTank: false, visible: false, pinned: true)

        XCTAssertEqual(settled(decider), .desktop)
    }

    /// Hiding the pet from the menu bar wins over everything: the answer to
    /// "where is the pet" is "nowhere" until it is shown again.
    func test_aHiddenPetIsNotMovedAtAll() {
        let decider = PetHomeDecider()
        decider.isPetHidden = true
        decider.report(hasTank: true, visible: true, pinned: false)

        XCTAssertNil(settled(decider))
    }

    /// Nothing is emitted for a state the pet is already in -- the frame loop
    /// asks every frame and must not be told to move sixty times a second.
    func test_theSameStateIsReportedOnce() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true, pinned: false)
        XCTAssertEqual(settled(decider), .home)

        XCTAssertNil(settled(decider))
    }
}

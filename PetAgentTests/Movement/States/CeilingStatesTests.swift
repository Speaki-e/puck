//
//  CeilingStatesTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  ClimbToCeiling -> Ceiling -> Fall (2026-07-29 ceiling-crawling): climbs
//  straight up to the roamable area's top edge, then crawls upside-down
//  along it, bouncing off the horizontal bounds instead of falling off.
//

import XCTest
@testable import PetAgent

final class ClimbToCeilingStateTests: XCTestCase {
    func test_climbsStraightUpTowardTheCeiling() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 400))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertEqual(world.body.position.x, 100, "climbing straight up -- x must not drift")
        XCTAssertLessThan(world.body.position.y, 400, "should have climbed upward")
    }

    func test_arrivalAtTheCeilingRequestsCeilingTransition() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 10))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.first, .ceiling)
        XCTAssertEqual(world.body.position.y, 0, accuracy: MovementSolver.arrivalRadius)
    }

    func test_requestsCeilingOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 10))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }
}

final class CeilingStateTests: XCTestCase {
    func test_enter_flipsTheBodyUpsideDown() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = CeilingState(durationProvider: { 100 })
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertTrue(world.body.isUpsideDown)
    }

    func test_walksAlongTheCeiling_stayingWithinRoamableBounds() {
        let world = TestStateWorld(position: CGPoint(x: 490, y: 999))
        world.roamableArea = CGRect(x: 0, y: 0, width: 500, height: 500)
        let state = CeilingState(durationProvider: { 100 })
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertLessThanOrEqual(world.body.position.x, 500)
        XCTAssertGreaterThanOrEqual(world.body.position.x, 0)
        XCTAssertEqual(world.body.position.y, 0, "must crawl along the ceiling, not drift in Y")
    }

    func test_afterDurationElapses_requestsFall() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = CeilingState(durationProvider: { 1 })
        state.enter()

        world.run(state, seconds: 0.5)
        XCTAssertTrue(world.requestedTransitions.isEmpty)

        world.run(state, seconds: 1)
        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    func test_requestsFallOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = CeilingState(durationProvider: { 1 })
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }
}

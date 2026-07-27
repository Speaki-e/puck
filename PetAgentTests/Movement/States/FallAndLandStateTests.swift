//
//  FallAndLandStateTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  Fall -> Land -> Idle, the tail of the transition table in
//  plan/02_pet-app.md section 3. Fall is the only state with acceleration.
//

import XCTest
@testable import PetAgent

final class FallStateTests: XCTestCase {
    func test_acceleratesDownwardEachFrame() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000 // far below, so it never lands during this test
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.2)
        let afterFirstBurst = world.body.position.y
        world.run(state, seconds: 0.2)
        let afterSecondBurst = world.body.position.y

        XCTAssertGreaterThan(afterFirstBurst, 0, "the pet should be falling")
        XCTAssertGreaterThan(
            afterSecondBurst - afterFirstBurst,
            afterFirstBurst,
            "the second interval must cover more ground than the first"
        )
    }

    func test_landsOnTheSurfaceAndRequestsLand() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 200
        let state = FallState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.y, 200, accuracy: 0.001, "must stop on the surface, not sink through")
        XCTAssertEqual(world.requestedTransitions.first, .land)
    }

    func test_requestsLandOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 50
        let state = FallState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions, [.land])
    }

    /// Velocity must not carry over from a previous fall, or the second one
    /// starts at whatever speed the first ended with.
    func test_velocityResetsOnReentry() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        let state = FallState()

        state.enter()
        world.run(state, seconds: 1)
        let fastFall = world.body.position.y

        world.body.position = CGPoint(x: 100, y: 0)
        state.enter()
        world.run(state, seconds: 1)
        let freshFall = world.body.position.y

        XCTAssertEqual(fastFall, freshFall, accuracy: 1, "a re-entered fall starts from rest")
    }
}

final class LandStateTests: XCTestCase {
    func test_returnsToIdleAfterTheLandingBeat() {
        let world = TestStateWorld()
        let state = LandState()
        state.enter()

        world.run(state, seconds: 0.05)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the landing clip needs a moment to read")

        world.run(state, seconds: 1)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }
}

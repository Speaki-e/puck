//
//  BallPhysicsTests.swift
//  PetAgent
//
//  F12 test · owner: 박해영 (Haeyoung Park)
//  Pure physics for the ball-toy interaction (02_pet-app.md F12, optional).
//  Drop reuses MovementSolver.fallStep's free-fall math directly; the kicked
//  fling is this file's one bit of new arithmetic.
//

import XCTest
@testable import PetAgent

final class BallPhysicsTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    // MARK: - falling

    func test_falling_movesTowardLandingY() {
        let state = BallState(position: CGPoint(x: 100, y: 0), phase: .falling)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertGreaterThan(next.position.y, state.position.y)
        XCTAssertEqual(next.phase, .falling)
    }

    func test_falling_landsAndBecomesResting_onceItReachesLandingY() {
        let state = BallState(position: CGPoint(x: 100, y: 499), verticalVelocity: 1000, phase: .falling)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next.position.y, 500)
        XCTAssertEqual(next.phase, .resting)
        XCTAssertEqual(next.verticalVelocity, 0)
    }

    // MARK: - resting

    func test_resting_isANoOp() {
        let state = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next, state)
    }

    // MARK: - kick(_:direction:)

    func test_kick_facingRight_launchesRightAndUpward() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let kicked = BallPhysics.kick(resting, direction: .right)

        XCTAssertEqual(kicked.phase, .kicked)
        XCTAssertGreaterThan(kicked.horizontalVelocity, 0)
        XCTAssertLessThan(kicked.verticalVelocity, 0) // negative = upward (Y increases downward)
        XCTAssertEqual(kicked.kickedElapsed, 0)
    }

    func test_kick_facingLeft_launchesLeft() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let kicked = BallPhysics.kick(resting, direction: .left)

        XCTAssertLessThan(kicked.horizontalVelocity, 0)
    }

    // MARK: - kicked

    func test_kicked_movesByBothVelocitiesAndApplesGravity() {
        let state = BallState(position: CGPoint(x: 100, y: 500), verticalVelocity: -400, horizontalVelocity: 260, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next.position.x, 100 + 26, accuracy: 0.001) // 260 * 0.1
        // y moves by (updated velocity) * dt, not the old velocity -- confirms gravity was applied first.
        let expectedVelocity = -400 + MovementSolver.gravity * 0.1
        XCTAssertEqual(next.verticalVelocity, expectedVelocity, accuracy: 0.001)
        XCTAssertEqual(next.position.y, 500 + expectedVelocity * 0.1, accuracy: 0.001)
    }

    func test_kicked_accumulatesElapsedTime() {
        let state = BallState(position: .zero, horizontalVelocity: 100, phase: .kicked, kickedElapsed: 0.2)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next.kickedElapsed, 0.3, accuracy: 0.0001)
    }

    func test_kicked_becomesGone_afterItsLifetimeElapses() {
        let state = BallState(position: CGPoint(x: 500, y: 300), horizontalVelocity: 10, phase: .kicked, kickedElapsed: BallPhysics.kickedLifetime - 0.05)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .gone)
    }

    func test_kicked_becomesGone_onceItExitsTheRoamableAreaByAMargin() {
        // Far to the right of a 1000-wide area, past the "still visible enough
        // to bother rendering" margin.
        let state = BallState(position: CGPoint(x: 1400, y: 300), horizontalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .gone)
    }

    // MARK: - gone

    func test_gone_isANoOp() {
        let state = BallState(position: CGPoint(x: 100, y: 500), phase: .gone)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next, state)
    }
}

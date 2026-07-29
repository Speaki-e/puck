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

    // MARK: - juggle(_:) (F12 juggle-before-kick variety, 2026-07-29)

    /// byeolki's request for more diverse motions/interactions -- a small
    /// vertical pop that falls back down and rests again, reusing the exact
    /// same .falling->.resting arc a drop already takes (an upward initial
    /// velocity decelerates under gravity, peaks, then falls back down).
    func test_juggle_popsUpward_thenFallsBackViaTheExistingFallingPhase() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let juggled = BallPhysics.juggle(resting)

        XCTAssertEqual(juggled.phase, .falling)
        XCTAssertLessThan(juggled.verticalVelocity, 0) // negative = upward
        XCTAssertEqual(juggled.horizontalVelocity, 0, "a juggle pop is straight up, not off to the side")
    }

    func test_juggle_isWeakerThanAKick() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let juggled = BallPhysics.juggle(resting)
        let kicked = BallPhysics.kick(resting, direction: .right)

        XCTAssertGreaterThan(juggled.verticalVelocity, kicked.verticalVelocity, "less negative = a smaller pop than a full kick")
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

    /// The sides, the top and the floor now all hold a kicked toy in, so this
    /// backstop only fires when there is no surface under it at all.
    func test_kicked_becomesGone_whenThereIsNothingBelowToLandOn() {
        let state = BallState(position: CGPoint(x: 500, y: 1400), verticalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 99_999, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .gone)
    }

    // MARK: - A kicked toy comes back to rest

    func test_kicked_bouncesOffTheFloorInsteadOfFallingThroughIt() {
        let floor = roamableArea.maxY
        // Already at the floor, heading down hard.
        let state = BallState(position: CGPoint(x: 500, y: floor), verticalVelocity: 800, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.01, landingY: floor, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked, "still bouncing")
        XCTAssertLessThan(next.verticalVelocity, 0, "heading back up")
        XCTAssertLessThanOrEqual(next.position.y, floor, "never below the surface")
    }

    /// An ordinary kick settles back into play rather than disappearing, so
    /// the pet can chase it again.
    func test_anOrdinaryKickSettlesBackToResting() {
        let floor = roamableArea.maxY
        var state = BallPhysics.kick(
            BallState(position: CGPoint(x: 500, y: floor), phase: .resting),
            direction: .right
        )

        for _ in 0..<600 where state.phase == .kicked {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
            XCTAssertLessThanOrEqual(state.position.y, floor + 0.01, "fell through the floor")
        }

        XCTAssertEqual(state.phase, .resting)
        XCTAssertEqual(state.position.y, floor, accuracy: 0.01, "resting on the surface")
    }

    /// Even a bonk off the pet's head leaves the toy in play now -- it
    /// bounces away and settles rather than disappearing.
    func test_noKickEverEndsInTheToyDisappearing() {
        let floor = roamableArea.maxY
        var state = BallPhysics.kick(
            BallState(position: CGPoint(x: 500, y: floor), phase: .resting),
            direction: .right
        )

        for _ in 0..<600 where state.phase == .kicked {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
        }

        XCTAssertEqual(state.phase, .resting)
    }

    // MARK: - Screen edges (byeolki: "그 호박도 펫처럼 화면밖으로 못나가고 튕기게")

    func test_kicked_bouncesOffTheSideInsteadOfLeaving() {
        // Heading right, already past the right edge of a 1000-wide area.
        let state = BallState(position: CGPoint(x: 1010, y: 300), horizontalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.01, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked, "still in play")
        XCTAssertLessThan(next.horizontalVelocity, 0, "heading back the other way")
        XCTAssertLessThanOrEqual(next.position.x, 1000, "back inside the screen")
    }

    func test_kicked_bouncesOffTheCeiling() {
        // Travelling upward (negative Y) above the top of the area.
        let state = BallState(position: CGPoint(x: 500, y: -10), verticalVelocity: -1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.01, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked)
        XCTAssertGreaterThan(next.verticalVelocity, 0, "now coming back down")
        XCTAssertGreaterThanOrEqual(next.position.y, 0)
    }

    /// A hard kick must not tunnel out through a corner over many frames.
    func test_kicked_neverLeavesTheScreenSideways() {
        var state = BallState(position: CGPoint(x: 900, y: 300), horizontalVelocity: 4000, phase: .kicked)

        for _ in 0..<60 where state.phase == .kicked {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: 5000, roamableArea: roamableArea)
            XCTAssertGreaterThanOrEqual(state.position.x, 0, "left the screen on the left")
            XCTAssertLessThanOrEqual(state.position.x, 1000, "left the screen on the right")
        }
    }

    /// The toy's own outline decides where the wall is, exactly like the pet's.
    func test_kicked_bouncesOnItsArtworkNotItsCentre() {
        let outline = CGRect(x: -20, y: -20, width: 40, height: 40)
        // Centre still inside, but the artwork's right edge is past the wall.
        let state = BallState(position: CGPoint(x: 990, y: 300), horizontalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(
            state, dt: 0.01, landingY: 900, roamableArea: roamableArea, visualBounds: outline
        )

        XCTAssertLessThan(next.horizontalVelocity, 0, "a 40pt-wide toy is already touching the wall")
    }

    /// A falling toy dropped near the edge is held inside too.
    func test_falling_isContainedWithinTheScreen() {
        let outline = CGRect(x: -20, y: -20, width: 40, height: 40)
        let state = BallState(position: CGPoint(x: 1200, y: 100), phase: .falling)

        let next = BallPhysics.step(
            state, dt: 0.01, landingY: 900, roamableArea: roamableArea, visualBounds: outline
        )

        XCTAssertEqual(next.position.x, 980, accuracy: 0.01, "held at the wall by its own edge")
    }

    // MARK: - gone

    func test_gone_isANoOp() {
        let state = BallState(position: CGPoint(x: 100, y: 500), phase: .gone)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next, state)
    }
}

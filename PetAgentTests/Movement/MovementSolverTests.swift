//
//  MovementSolverTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  The pure motion arithmetic behind MoveTo/Walk. plan/02_pet-app.md F3:
//  "물리엔진 없음. MoveTo 등속(px/sec) + 도착 반경, Fall만 낙하 가속도".
//  Positions are GlobalScreenSpace pixels (top-left origin, Y down).
//

import XCTest
@testable import PetAgent

final class MovementSolverTests: XCTestCase {
    // MARK: - Constant-velocity step

    func test_movesTowardTargetAtConstantSpeed() {
        let step = MovementSolver.step(
            from: CGPoint(x: 0, y: 0),
            toward: CGPoint(x: 100, y: 0),
            speed: 200,
            dt: 0.1,
            arrivalRadius: 1
        )

        XCTAssertEqual(step.position.x, 20, accuracy: 0.001, "200px/s for 0.1s = 20px")
        XCTAssertEqual(step.position.y, 0, accuracy: 0.001)
        XCTAssertFalse(step.hasArrived)
    }

    func test_speedIsIndependentOfDirection() {
        // A diagonal target must still advance exactly speed*dt, not speed*dt
        // per axis — that would make diagonal movement 1.41x too fast.
        let step = MovementSolver.step(
            from: .zero,
            toward: CGPoint(x: 100, y: 100),
            speed: 100,
            dt: 1,
            arrivalRadius: 1
        )

        let travelled = hypot(step.position.x, step.position.y)
        XCTAssertEqual(travelled, 100, accuracy: 0.001)
    }

    // MARK: - Arrival

    func test_reportsArrivalInsideTheRadius() {
        let step = MovementSolver.step(
            from: CGPoint(x: 99, y: 0),
            toward: CGPoint(x: 100, y: 0),
            speed: 200,
            dt: 0.1,
            arrivalRadius: 5
        )

        XCTAssertTrue(step.hasArrived)
    }

    /// Without clamping, a fast pet and a slow frame overshoot the target and
    /// then oscillate around it forever, never landing inside the radius.
    func test_doesNotOvershootTheTarget() {
        let step = MovementSolver.step(
            from: .zero,
            toward: CGPoint(x: 10, y: 0),
            speed: 1000,
            dt: 1, // would travel 1000px toward a target 10px away
            arrivalRadius: 1
        )

        XCTAssertEqual(step.position.x, 10, accuracy: 0.001, "must stop at the target, not past it")
        XCTAssertTrue(step.hasArrived)
    }

    func test_alreadyAtTarget_staysPutAndReportsArrival() {
        let step = MovementSolver.step(
            from: CGPoint(x: 50, y: 50),
            toward: CGPoint(x: 50, y: 50),
            speed: 200,
            dt: 0.1,
            arrivalRadius: 1
        )

        XCTAssertEqual(step.position, CGPoint(x: 50, y: 50))
        XCTAssertTrue(step.hasArrived)
    }

    // MARK: - Facing

    func test_facingFollowsHorizontalDirection() {
        XCTAssertEqual(MovementSolver.facing(from: .zero, toward: CGPoint(x: 10, y: 0)), .right)
        XCTAssertEqual(MovementSolver.facing(from: .zero, toward: CGPoint(x: -10, y: 0)), .left)
    }

    func test_facingIsUnchangedForPurelyVerticalMotion() {
        XCTAssertNil(
            MovementSolver.facing(from: .zero, toward: CGPoint(x: 0, y: 50)),
            "climbing straight up must not flip the character"
        )
    }

    // MARK: - Falling

    func test_fallAcceleratesDownward() {
        // Y grows downward in GlobalScreenSpace.
        let first = MovementSolver.fallStep(position: .zero, velocity: 0, gravity: 1000, dt: 0.1)
        XCTAssertEqual(first.velocity, 100, accuracy: 0.001)
        XCTAssertGreaterThan(first.position.y, 0)

        let second = MovementSolver.fallStep(position: first.position, velocity: first.velocity, gravity: 1000, dt: 0.1)
        XCTAssertEqual(second.velocity, 200, accuracy: 0.001)
        XCTAssertGreaterThan(
            second.position.y - first.position.y,
            first.position.y,
            "the second frame must cover more ground than the first"
        )
    }

    /// Falling from the ceiling (F3, 2026-07-29) covers far more distance
    /// than falling off a window ever did, so unbounded acceleration
    /// eventually moves the pet dozens of pixels in a single frame -- reads
    /// as a teleport, not a fall (byeolki: "떨어지다가 개빨라져서 거의
    /// 순간이동임"). A terminal velocity keeps per-frame movement bounded no
    /// matter how far the drop.
    func test_fallVelocityIsCappedAtTerminalVelocity() {
        let step = MovementSolver.fallStep(
            position: .zero,
            velocity: 2000, // already above any reasonable terminal velocity
            gravity: 1000,
            dt: 1,
            terminalVelocity: 900
        )

        XCTAssertEqual(step.velocity, 900, accuracy: 0.001)
    }

    /// byeolki: "이새끼 창위에 있다가 떨어지는 속도가 너무 느림. 내가 잡아서
    /// 위에서 놓아서 떨어지는 속도랑 너무 다름" -- a short fall (off a
    /// window) must ramp up to terminal velocity within a much shorter
    /// distance than it takes to fall the length of the whole screen (a
    /// manual drop from near the top), or it never gets past "floaty" before
    /// it lands. Uses the DEFAULT gravity/terminalVelocity (no override) so
    /// this pins the actual live tuning, not just the math.
    func test_defaultGravity_reachesTerminalVelocityWithinAShortFall() {
        var velocity: CGFloat = 0
        var position = CGPoint.zero
        let dt: TimeInterval = 1.0 / 60
        var elapsed: TimeInterval = 0

        while velocity < MovementSolver.terminalVelocity, elapsed < 2 {
            let step = MovementSolver.fallStep(position: position, velocity: velocity, dt: dt)
            position = step.position
            velocity = step.velocity
            elapsed += dt
        }

        XCTAssertLessThan(position.y, 250, "should reach terminal velocity within roughly a window's height of falling")
    }

    func test_fallVelocityBelowTerminal_acceleratesNormally() {
        let step = MovementSolver.fallStep(
            position: .zero,
            velocity: 0,
            gravity: 1000,
            dt: 0.1,
            terminalVelocity: 900
        )

        XCTAssertEqual(step.velocity, 100, accuracy: 0.001)
    }

    func test_fallStopsAtTheLandingSurface() {
        let step = MovementSolver.fallStep(
            position: CGPoint(x: 0, y: 95),
            velocity: 1000,
            gravity: 1000,
            dt: 1,
            landingY: 100
        )

        XCTAssertEqual(step.position.y, 100, accuracy: 0.001, "must not sink through the surface")
        XCTAssertTrue(step.hasLanded)
    }
}

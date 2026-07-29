//
//  BallStatesTests.swift
//  PetAgent
//
//  F12 test · owner: 박해영 (Haeyoung Park)
//  "Idle/Walk 한정 | 공 던지기(F12) | ChaseBall → KickBall → Idle"
//  (plan/02_pet-app.md section 3, optional ball-toy interaction).
//

import XCTest
@testable import PetAgent

final class ChaseBallStateTests: XCTestCase {
    func test_movesTowardTheBallAndRequestsKickOnArrival() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = ChaseBallState()
        state.target = CGPoint(x: 30, y: 100)
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.x, 30, accuracy: MovementSolver.arrivalRadius)
        XCTAssertEqual(world.requestedTransitions, [.kickBall])
    }

    func test_ignoresWindowsInTheWay_likeMoveTo() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [
            WindowInfo(windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0,
                       frame: CGRect(x: 300, y: 200, width: 400, height: 400))
        ]
        let state = ChaseBallState()
        state.target = CGPoint(x: 900, y: 500)
        state.enter()

        world.run(state, seconds: 12)

        XCTAssertFalse(world.requestedTransitions.contains(.climb))
        XCTAssertEqual(world.body.position.x, 900, accuracy: MovementSolver.arrivalRadius)
    }

    func test_withoutATarget_requestsIdleInstead() {
        let world = TestStateWorld()
        let state = ChaseBallState()
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    func test_handsOverOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = ChaseBallState()
        state.target = CGPoint(x: 5, y: 100)
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }

    /// Settings' movement-speed slider (byeolki's request, 2026-07-29).
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        world.walkSpeed = MovementSolver.walkSpeed * 2
        let state = ChaseBallState()
        state.target = CGPoint(x: 1000, y: 100)
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertEqual(world.body.position.x, MovementSolver.walkSpeed * 2, accuracy: 1)
    }
}

final class KickBallStateTests: XCTestCase {
    func test_firesOnEnterOnceWhenEntered() {
        let world = TestStateWorld()
        let state = KickBallState()
        var kickCount = 0
        state.onEnter = { kickCount += 1 }

        state.enter()

        XCTAssertEqual(kickCount, 1)
    }

    func test_returnsToIdleAfterTheKickPlays() {
        let world = TestStateWorld()
        let state = KickBallState()
        state.enter()

        world.run(state, seconds: 0.05)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the kick clip needs a moment to read")

        world.run(state, seconds: 2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }
}

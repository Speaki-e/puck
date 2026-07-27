//
//  WindowWalkingTests.swift
//  PetAgent
//
//  F3/F4 test · owner: 박해영 (Haeyoung Park)
//  The window half of the transition table (plan/02_pet-app.md section 3):
//  Walk -> Climb at a window edge, Climb -> WalkOnTop at the top, WalkOnTop ->
//  Fall when the supporting window goes away.
//
//  Window frames arrive in the same space as the pet's position: overlay-local
//  pixels, top-left origin, Y down. AppDelegate converts F4's global Quartz
//  frames into that space before they reach a state.
//

import XCTest
@testable import PetAgent

private func window(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, id: CGWindowID = 1) -> WindowInfo {
    WindowInfo(
        windowID: id,
        ownerPID: 1234,
        ownerName: "Test",
        title: nil,
        layer: 0,
        frame: CGRect(x: x, y: y, width: width, height: height)
    )
}

final class WalkStateWindowTests: XCTestCase {
    /// Walking into the side of a window is what starts a climb — the pet
    /// shouldn't walk through it.
    func test_reachingAWindowEdge_requestsClimb() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = WalkState()
        state.target = CGPoint(x: 900, y: 500) // straight through the window

        world.run(state, seconds: 5)

        XCTAssertEqual(world.requestedTransitions.first, .climb)
        XCTAssertEqual(world.body.position.x, 300, accuracy: MovementSolver.arrivalRadius + 1)
    }

    func test_windowOutOfTheWay_doesNotInterruptTheWalk() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [window(x: 300, y: 20, width: 400, height: 100)] // far above the pet
        let state = WalkState()
        state.target = CGPoint(x: 400, y: 500)

        world.run(state, seconds: 5)

        XCTAssertEqual(world.requestedTransitions, [.idle], "no window in the pet's path")
    }
}

final class ClimbStateTests: XCTestCase {
    func test_climbsUpToTheWindowTopThenWalksOnIt() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertEqual(world.body.position.y, 200, accuracy: MovementSolver.arrivalRadius + 1)
        XCTAssertEqual(world.requestedTransitions.first, .walkOnTop)
    }

    /// Climbing is vertical; flipping the character partway up looks wrong.
    func test_doesNotChangeFacingWhileClimbing() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertTrue(world.avatar.facings.isEmpty)
    }

    func test_withNoWindowToClimb_falls() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.windows = []
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 0.5)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }
}

final class WalkOnTopStateTests: XCTestCase {
    func test_supportingWindowDisappears_falls() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 200))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 0.5)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "still supported")

        world.windows = [] // window closed or minimized
        world.run(state, seconds: 0.5)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    /// Walking off the end of a window top is the same situation as the
    /// window vanishing: nothing underfoot.
    func test_walkingPastTheWindowEdge_falls() {
        let world = TestStateWorld(position: CGPoint(x: 690, y: 200))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)] // right edge at 700
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }
}

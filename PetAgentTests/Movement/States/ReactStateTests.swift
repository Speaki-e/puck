//
//  ReactStateTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  "임의 | 캐릭터 클릭 | ReactClick → Idle" and "임의 | 캐릭터 드래그/드롭 |
//  ReactDrag(커서 추종) → Fall" (plan/02_pet-app.md section 3).
//

import XCTest
@testable import PetAgent

final class ReactClickStateTests: XCTestCase {
    func test_returnsToIdleAfterTheReactionPlays() {
        let world = TestStateWorld()
        let state = ReactClickState()
        state.enter()

        world.run(state, seconds: 0.05)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the reaction clip needs a moment to read")

        world.run(state, seconds: 2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    /// Clicking the pet repeatedly should replay the reaction, not queue up a
    /// backlog of transitions from the first one.
    func test_reentryRestartsTheTimer() {
        let world = TestStateWorld()
        let state = ReactClickState()

        state.enter()
        world.run(state, seconds: 2)
        state.enter()
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.requestedTransitions.count, 1, "the second reaction has not finished yet")
    }
}

final class PettingStateTests: XCTestCase {
    func test_returnsToIdleAfterTheReactionPlays() {
        let world = TestStateWorld()
        let state = PettingState()
        state.enter()

        world.run(state, seconds: 0.1)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the wiggle needs a moment to read")

        world.run(state, seconds: 2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    /// Petting the pet again while it's still reacting should replay the
    /// reaction, not queue up a backlog of transitions from the first one.
    func test_reentryRestartsTheTimer() {
        let world = TestStateWorld()
        let state = PettingState()

        state.enter()
        world.run(state, seconds: 2)
        state.enter()
        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions.count, 1, "the second reaction has not finished yet")
    }
}

final class ReactDragStateTests: XCTestCase {
    func test_followsTheCursor() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()

        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 1) // long enough for the ease to converge

        XCTAssertEqual(world.body.position.x, 300, accuracy: 0.5)
        XCTAssertEqual(world.body.position.y, 150, accuracy: 0.5)
    }

    /// A small amount of "give" while being carried instead of snapping
    /// exactly to the cursor every frame, which reads as a rigid teleport
    /// rather than something being held (byeolki: "내가 잡고 움직일때
    /// 아직 움직임이 부자연스러워").
    func test_doesNotSnapInstantlyToTheCursor() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()

        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 1.0 / 60) // exactly one frame

        XCTAssertGreaterThan(world.body.position.x, 0, "should have moved toward the cursor")
        XCTAssertLessThan(world.body.position.x, 300, "but not all the way there in a single frame")
    }

    func test_releasingDropsThePet() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 0.05)

        state.release()
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    /// The pet must stay where it was dropped rather than snapping back to
    /// wherever the cursor wandered afterwards.
    func test_afterRelease_stopsFollowingTheCursor() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 1) // converge close to the cursor first
        let droppedPosition = world.body.position

        state.release()
        world.run(state, seconds: 0.05)

        state.cursorPosition = CGPoint(x: 900, y: 900)
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.body.position, droppedPosition)
    }

    func test_facesTheDirectionItIsDraggedIn() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 0))
        let state = ReactDragState()
        state.enter()

        state.cursorPosition = CGPoint(x: 100, y: 0)
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.avatar.facings.last, .left)
    }
}

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
    /// One frame to register the grab, then the cursor moves. Mirrors how
    /// AppDelegate feeds .dragBegan and then .dragMoved.
    private func grab(_ state: ReactDragState, at point: CGPoint, in world: TestStateWorld) {
        state.cursorPosition = point
        world.run(state, seconds: 1.0 / 60)
    }

    /// Dragging a window keeps the grabbed point under the cursor; grabbing
    /// the pet must not re-center it on the cursor either (byeolki: "구글 창
    /// 같은걸 드래그 할때처럼").
    func test_grabbingDoesNotMoveThePet() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 400))
        let state = ReactDragState()
        state.enter()

        // Grabbed 30px to the left of and 20px above the pet's origin.
        grab(state, at: CGPoint(x: 470, y: 380), in: world)

        XCTAssertEqual(world.body.position, CGPoint(x: 500, y: 400))
    }

    func test_followsTheCursor_keepingTheGrabOffset() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 400))
        let state = ReactDragState()
        state.enter()
        grab(state, at: CGPoint(x: 470, y: 380), in: world)

        state.cursorPosition = CGPoint(x: 570, y: 430) // cursor moved +100, +50
        world.run(state, seconds: 1)

        // The pet moved by the same delta, offset intact.
        XCTAssertEqual(world.body.position.x, 600, accuracy: 0.5)
        XCTAssertEqual(world.body.position.y, 450, accuracy: 0.5)
    }

    /// The pet is carried, not moving under its own power (byeolki: "이동한다는
    /// 개념이 아니라 잡고 끌려간다는 개념"), so it has no speed of its own to
    /// lag behind at: it is wherever the cursor is on the very next frame,
    /// however far the cursor jumped.
    func test_tracksTheCursorWithinASingleFrame_howeverFarItMoved() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        state.cursorPosition = CGPoint(x: 20, y: 10) // an ordinary drag
        world.run(state, seconds: 1.0 / 60) // exactly one frame
        XCTAssertEqual(world.body.position, CGPoint(x: 20, y: 10))

        state.cursorPosition = CGPoint(x: 2000, y: 10) // a hard flick
        world.run(state, seconds: 1.0 / 60)
        XCTAssertEqual(world.body.position, CGPoint(x: 2000, y: 10), "stays stuck to the cursor")
    }

    func test_releasingDropsThePet() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)
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
        grab(state, at: .zero, in: world)
        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 1)
        let droppedPosition = world.body.position

        state.release()
        world.run(state, seconds: 0.05)

        state.cursorPosition = CGPoint(x: 900, y: 900)
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.body.position, droppedPosition)
    }

    // MARK: - Throwing (byeolki: "드래그해서 던지면 던져지게", 2026-07-29)

    /// Drags the cursor at a steady `speed` px/sec to the right for `seconds`.
    private func swipe(_ state: ReactDragState, speed: CGFloat, seconds: TimeInterval, in world: TestStateWorld) {
        let frame = 1.0 / 60
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            let cursor = state.cursorPosition ?? .zero
            state.cursorPosition = CGPoint(x: cursor.x + speed * CGFloat(frame), y: cursor.y)
            world.run(state, seconds: frame)
            elapsed += frame
        }
    }

    func test_releasingMidSwipeThrowsThePet() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        swipe(state, speed: 800, seconds: 0.3, in: world)
        state.release()
        world.run(state, seconds: 1.0 / 60)

        XCTAssertEqual(world.body.launchVelocity.x, 800, accuracy: 80, "thrown at the speed it was swiped")
        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    /// Letting go of a stationary cursor is a drop, not a throw — the pet must
    /// fall straight down the way it always did.
    func test_releasingAStillCursorThrowsNothing() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        swipe(state, speed: 800, seconds: 0.3, in: world)
        world.run(state, seconds: 0.5) // held still before letting go
        state.release()
        world.run(state, seconds: 1.0 / 60)

        // The smoothing decays rather than hard-resetting, so a couple of px/s
        // survives half a second of stillness — under 1/300th of the swipe,
        // and less than a tenth of a pixel of drift over the whole fall.
        XCTAssertEqual(world.body.launchVelocity.x, 0, accuracy: 5)
    }

    func test_aViolentFlickIsCappedAtMaxThrowSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        swipe(state, speed: 12_000, seconds: 0.3, in: world)
        state.release()
        world.run(state, seconds: 1.0 / 60)

        XCTAssertEqual(world.body.launchVelocity.x, MovementSolver.maxThrowSpeed, accuracy: 0.001)
    }

    /// A new grab must not inherit the previous throw's speed.
    func test_velocityResetsOnReentry() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)
        swipe(state, speed: 800, seconds: 0.3, in: world)

        state.enter() // grabbed again
        grab(state, at: world.body.position, in: world)
        state.release()
        world.run(state, seconds: 1.0 / 60)

        XCTAssertEqual(world.body.launchVelocity, .zero)
    }

    func test_facesTheDirectionItIsDraggedIn() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: CGPoint(x: 500, y: 0), in: world)

        state.cursorPosition = CGPoint(x: 100, y: 0)
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.avatar.facings.last, .left)
    }
}

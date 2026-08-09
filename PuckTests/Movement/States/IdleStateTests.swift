//
//  IdleStateTests.swift
//  Puck
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  IdleState's wander-timer -> delegate callback wiring.
//

import XCTest
@testable import Puck

final class IdleStateTests: XCTestCase {
    private final class SpyWanderDelegate: IdleWanderDelegate {
        private(set) var received: [WanderScheduler.Outcome] = []
        func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome) { received.append(outcome) }
    }

    func test_update_notifiesDelegate_whenWanderTimerFires() {
        let scheduler = WanderScheduler(nextIntervalProvider: { 8 }, outcomeProvider: { .walkToRandomPoint })
        let state = IdleState(scheduler: scheduler)
        let delegate = SpyWanderDelegate()
        state.wanderDelegate = delegate
        let world = TestStateWorld()
        world.landingY = 0 // already resting on the ground -- not falling

        state.update(dt: 8, context: world.context)

        XCTAssertEqual(delegate.received, [.walkToRandomPoint])
    }

    func test_metadata_matchesManifestIdleClip() {
        let state = IdleState()

        XCTAssertEqual(state.name, "Idle")
        XCTAssertEqual(state.clipKey, "idle")
        XCTAssertTrue(state.loopsClip)
    }

    // MARK: - Ground disappearing (F4, 2026-07-29)

    /// After Fall -> Land -> Idle, the pet can be resting on a window's top
    /// edge (LandingSurfaceResolver treats window tops as valid landing
    /// surfaces) -- if that window closes or minimizes while the pet is
    /// idling there, nothing previously checked for it (only WalkOnTopState
    /// did). byeolki: "창에 올려두고 화면에서 창이 없어지면 자동으로
    /// 떨어지게 해줘".
    func test_theSupportingSurfaceDisappearing_requestsFall() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 200))
        world.landingY = 200 // resting exactly on a window's top edge
        let state = IdleState()

        state.update(dt: 0.1, context: world.context)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "still supported")

        world.landingY = 900 // the window closed -- nothing until the floor
        state.update(dt: 0.1, context: world.context)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    func test_stillSupported_doesNotRequestFall() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 500))
        world.landingY = 500
        let state = IdleState()

        world.run(state, seconds: 5) // below the scheduler's 8s minimum interval

        XCTAssertTrue(world.requestedTransitions.isEmpty)
    }
}

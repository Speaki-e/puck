//
//  IdleStateTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  IdleState's wander-timer -> delegate callback wiring.
//

import XCTest
@testable import PetAgent

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

        state.update(dt: 8, context: TestStateWorld().context)

        XCTAssertEqual(delegate.received, [.walkToRandomPoint])
    }

    func test_metadata_matchesManifestIdleClip() {
        let state = IdleState()

        XCTAssertEqual(state.name, "Idle")
        XCTAssertEqual(state.clipKey, "idle")
        XCTAssertTrue(state.loopsClip)
    }
}

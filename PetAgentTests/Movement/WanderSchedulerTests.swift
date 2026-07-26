//
//  WanderSchedulerTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  Deterministic timer-accumulation behavior of WanderScheduler (interval/outcome
//  providers injected so the random 8-30s wander timer is testable).
//

import XCTest
@testable import PetAgent

final class WanderSchedulerTests: XCTestCase {
    func test_tick_returnsNil_beforeIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { 10 }, outcomeProvider: { .walkToRandomPoint })

        XCTAssertNil(scheduler.tick(dt: 5))
        XCTAssertNil(scheduler.tick(dt: 4.9))
    }

    func test_tick_firesOutcome_onceIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { 10 }, outcomeProvider: { .climbNearestWindow })

        XCTAssertNil(scheduler.tick(dt: 9))
        XCTAssertEqual(scheduler.tick(dt: 1), .climbNearestWindow)
    }

    func test_tick_resetsElapsedAndPicksNextInterval() {
        var intervals: [TimeInterval] = [10, 3]
        let scheduler = WanderScheduler(
            nextIntervalProvider: { intervals.isEmpty ? 999 : intervals.removeFirst() },
            outcomeProvider: { .stay }
        )

        XCTAssertEqual(scheduler.tick(dt: 10), .stay) // first timer (10) expires, next timer (3) is drawn
        XCTAssertNil(scheduler.tick(dt: 2))
        XCTAssertEqual(scheduler.tick(dt: 1), .stay) // second timer (3) expires
    }
}

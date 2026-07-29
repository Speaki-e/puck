//
//  WanderSchedulerTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  Deterministic timer-accumulation behavior of WanderScheduler (interval/outcome
//  providers injected so the wander timer is testable).
//

import XCTest
@testable import PetAgent

final class WanderSchedulerTests: XCTestCase {
    /// Every other test here injects its own interval, so without this the
    /// value the app actually ships with is covered by nothing.
    func test_defaultInterval_keepsThePetVisiblyActive() {
        XCTAssertEqual(WanderScheduler.defaultInterval, 5)

        // And the default initializer really uses it -- the provider default
        // and the constant can drift apart otherwise.
        let scheduler = WanderScheduler(outcomeProvider: { .walkToRandomPoint })
        XCTAssertNil(scheduler.tick(dt: WanderScheduler.defaultInterval - 0.1))
        XCTAssertEqual(scheduler.tick(dt: 0.1), .walkToRandomPoint)
    }

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

    /// F3 ceiling-crawling (2026-07-29): a fourth Outcome case alongside walk/climb/stay.
    func test_tick_firesClimbToCeilingOutcome_onceIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { 10 }, outcomeProvider: { .climbToCeiling })

        XCTAssertNil(scheduler.tick(dt: 9))
        XCTAssertEqual(scheduler.tick(dt: 1), .climbToCeiling)
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

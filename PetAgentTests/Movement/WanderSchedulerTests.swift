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
    func test_defaultIntervalRange_isLivelyWithoutBeingConstantMotion() {
        XCTAssertEqual(WanderScheduler.defaultIntervalRange, 8...15)
    }

    /// The provider default and the constant can drift apart, and a fixed
    /// interval makes the pet metronomic -- so pin that the shipped default
    /// both draws from the range and actually varies.
    func test_defaultInitializer_drawsVaryingIntervalsFromTheRange() {
        let range = WanderScheduler.defaultIntervalRange
        var firedAt: [TimeInterval] = []

        for _ in 0..<40 {
            let scheduler = WanderScheduler(outcomeProvider: { .walkToRandomPoint })
            var elapsed: TimeInterval = 0
            while scheduler.tick(dt: 0.1) == nil {
                elapsed += 0.1
                if elapsed > range.upperBound + 1 { break }
            }
            firedAt.append(elapsed)
        }

        for interval in firedAt {
            XCTAssertGreaterThanOrEqual(interval, range.lowerBound - 0.1)
            XCTAssertLessThanOrEqual(interval, range.upperBound)
        }
        XCTAssertGreaterThan(Set(firedAt).count, 1, "a fixed interval would make the pet metronomic")
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

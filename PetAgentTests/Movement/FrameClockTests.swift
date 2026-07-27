//
//  FrameClockTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  The Timer half — that starting the clock actually delivers ticks on the
//  main run loop, and that stopping it stops them. Timing bounds are
//  deliberately loose; the exact dt arithmetic is FrameTickerTests' job.
//

import XCTest
@testable import PetAgent

final class FrameClockTests: XCTestCase {
    func test_start_deliversRepeatedTicksWithPositiveDeltas() {
        let clock = FrameClock(framesPerSecond: 60)

        var deltas: [TimeInterval] = []
        let gotEnoughTicks = expectation(description: "clock ticked repeatedly")
        gotEnoughTicks.expectedFulfillmentCount = 5
        clock.onTick = { dt in
            deltas.append(dt)
            gotEnoughTicks.fulfill()
        }

        clock.start()
        wait(for: [gotEnoughTicks], timeout: 3)
        clock.stop()

        XCTAssertTrue(deltas.allSatisfy { $0 > 0 }, "every frame must report a positive dt: \(deltas)")
        XCTAssertTrue(deltas.allSatisfy { $0 <= FrameTicker().maxDelta }, "dt must stay clamped: \(deltas)")
    }

    func test_stop_endsTickDelivery() {
        let clock = FrameClock(framesPerSecond: 60)

        var tickCount = 0
        clock.onTick = { _ in tickCount += 1 }
        clock.start()

        let ticked = expectation(description: "clock started ticking")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ticked.fulfill() }
        wait(for: [ticked], timeout: 2)
        clock.stop()

        let countAtStop = tickCount
        XCTAssertGreaterThan(countAtStop, 0, "precondition: the clock should have been running")

        let settled = expectation(description: "waited past several would-be frames")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(tickCount, countAtStop, "ticks continued after stop()")
    }

    func test_setFramesPerSecond_isIgnoredForNonPositiveRates() {
        let clock = FrameClock(framesPerSecond: 60)

        clock.setFramesPerSecond(0)
        XCTAssertEqual(clock.framesPerSecond, 60)

        clock.setFramesPerSecond(FrameClock.idleFramesPerSecond)
        XCTAssertEqual(clock.framesPerSecond, FrameClock.idleFramesPerSecond)
    }
}

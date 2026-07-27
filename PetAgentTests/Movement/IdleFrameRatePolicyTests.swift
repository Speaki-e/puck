//
//  IdleFrameRatePolicyTests.swift
//  PetAgent
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  plan/02_pet-app.md F1: "Idle 30초 지속 시 프레임레이트 60→15 다운시프트".
//  FrameClock could already change rate; nothing decided when to. A pet
//  standing still was measured holding ~20% CPU.
//

import XCTest
@testable import PetAgent

final class IdleFrameRatePolicyTests: XCTestCase {
    func test_runsAtFullRateWhileTheStateIsNotIdle() {
        var policy = IdleFrameRatePolicy()

        XCTAssertEqual(policy.framesPerSecond(idle: false, dt: 60), FrameClock.activeFramesPerSecond)
    }

    func test_staysAtFullRateUntilTheIdleThreshold() {
        var policy = IdleFrameRatePolicy(threshold: 30)

        _ = policy.framesPerSecond(idle: true, dt: 29)
        XCTAssertEqual(policy.framesPerSecond(idle: true, dt: 0.5), FrameClock.activeFramesPerSecond)
    }

    func test_downshiftsOncePastTheThreshold() {
        var policy = IdleFrameRatePolicy(threshold: 30)

        _ = policy.framesPerSecond(idle: true, dt: 29)
        XCTAssertEqual(policy.framesPerSecond(idle: true, dt: 2), FrameClock.idleFramesPerSecond)
    }

    /// The pet has to react immediately when something happens — coming back
    /// up to speed a second later would show as a visible stutter.
    func test_leavingIdleRestoresFullRateAtOnce() {
        var policy = IdleFrameRatePolicy(threshold: 30)
        _ = policy.framesPerSecond(idle: true, dt: 40)

        XCTAssertEqual(policy.framesPerSecond(idle: false, dt: 0.016), FrameClock.activeFramesPerSecond)
    }

    func test_idleTimerRestartsAfterActivity() {
        var policy = IdleFrameRatePolicy(threshold: 30)
        _ = policy.framesPerSecond(idle: true, dt: 40)
        _ = policy.framesPerSecond(idle: false, dt: 0.016)

        XCTAssertEqual(
            policy.framesPerSecond(idle: true, dt: 5),
            FrameClock.activeFramesPerSecond,
            "only 5s idle since the last activity"
        )
    }
}

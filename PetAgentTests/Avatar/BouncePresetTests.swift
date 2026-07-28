//
//  BouncePresetTests.swift
//  PetAgent
//
//  F2 test · owner: 박해영 (Haeyoung Park)
//  Pure math for the 2026-07-29 2D switch's procedural squash-and-stretch
//  "bounce" motion (02_pet-app.md F2) -- no rendering, no timers, just
//  elapsed-time-in, transform-out.
//

import XCTest
@testable import PetAgent

final class BouncePresetTests: XCTestCase {
    // MARK: - preset(for:) mapping

    func test_preset_mapsIdleWalkLand() {
        XCTAssertEqual(BouncePreset.preset(for: "idle"), .idle)
        XCTAssertEqual(BouncePreset.preset(for: "walk"), .walk)
        XCTAssertEqual(BouncePreset.preset(for: "land"), .land)
    }

    func test_preset_mapsPointAndReactClickToPop() {
        XCTAssertEqual(BouncePreset.preset(for: "point"), .pop)
        XCTAssertEqual(BouncePreset.preset(for: "react_click"), .pop)
    }

    func test_preset_mapsKickToKick() {
        XCTAssertEqual(BouncePreset.preset(for: "kick"), .kick)
    }

    func test_preset_mapsUnhandledClipsToNone() {
        for clip in ["climb", "fall", "type", "listen", "react_drag", "not_a_real_clip"] {
            XCTAssertEqual(BouncePreset.preset(for: clip), .none, "expected .none for \(clip)")
        }
    }

    // MARK: - intensity 0 / .none -> always identity

    func test_transform_zeroIntensity_isAlwaysIdentity() {
        for preset: BouncePreset in [.idle, .walk, .land, .pop, .kick] {
            let transform = preset.transform(elapsed: 1.0, intensity: 0)
            XCTAssertEqual(transform, .identity, "expected identity for \(preset) at intensity 0")
        }
    }

    func test_transform_noneCase_isAlwaysIdentityRegardlessOfIntensity() {
        XCTAssertEqual(BouncePreset.none.transform(elapsed: 0.5, intensity: 1.0), .identity)
    }

    // MARK: - idle: slow bob

    func test_idle_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.idle.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    func test_idle_atQuarterPeriod_peaksScaleYAboveOne() {
        let period = 2.5
        let transform = BouncePreset.idle.transform(elapsed: period / 4, intensity: 1.0)
        XCTAssertGreaterThan(transform.scaleY, 1.0)
    }

    // MARK: - walk: faster bounce

    func test_walk_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.walk.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    // MARK: - land: squash on impact, springs back

    func test_land_atZeroElapsed_squashesAtFullIntensity() {
        let transform = BouncePreset.land.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.3, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.7, accuracy: 0.0001)
    }

    func test_land_decaysToIdentity_wellAfterItsDuration() {
        let transform = BouncePreset.land.transform(elapsed: 5.0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.01)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.01)
    }

    // MARK: - pop: point/react_click pulse

    func test_pop_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.pop.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    func test_pop_atHalfDuration_peaksAboveOne() {
        let transform = BouncePreset.pop.transform(elapsed: 0.125, intensity: 1.0) // duration 0.25
        XCTAssertEqual(transform.scaleX, 1.15, accuracy: 0.001)
        XCTAssertEqual(transform.scaleY, 1.15, accuracy: 0.001)
    }

    func test_pop_afterDuration_staysAtRest() {
        // t is clamped past 1.0, so sin(pi) == 0 -- not decaying further, just resting.
        let transform = BouncePreset.pop.transform(elapsed: 10, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    // MARK: - kick: anticipation squash, then impact stretch

    func test_kick_earlyElapsed_squashesInAnticipation() {
        let transform = BouncePreset.kick.transform(elapsed: 0.1, intensity: 1.0) // < 0.4 * 0.4 = 0.16 threshold
        XCTAssertGreaterThan(transform.scaleX, 1.0)
        XCTAssertLessThan(transform.scaleY, 1.0)
    }

    func test_kick_lateElapsed_stretchesOnImpact() {
        let transform = BouncePreset.kick.transform(elapsed: 0.3, intensity: 1.0) // past the 0.16s anticipation threshold
        XCTAssertLessThan(transform.scaleX, 1.0)
        XCTAssertGreaterThan(transform.scaleY, 1.0)
    }
}

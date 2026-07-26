//
//  StateTransitionTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  Verifies CharacterController's state transition lifecycle (enter/exit,
//  avatar clip + SFX trigger) per plan/02_pet-app.md section 3.
//

import XCTest
import CoreGraphics
@testable import PetAgent

// MARK: - Test doubles

final class SpyAvatarPlayable: AvatarPlayable {
    private(set) var playedClips: [(clip: String, loop: Bool)] = []
    private(set) var stopCallCount = 0

    func play(clip: String, loop: Bool) { playedClips.append((clip, loop)) }
    func stop() { stopCallCount += 1 }
    func setScreenPosition(_ position: CGPoint) {}
    func setFacing(_ facing: AvatarFacing) {}
}

final class SpySFXTriggering: SFXTriggering {
    private(set) var triggeredKeys: [String] = []
    func trigger(_ key: String) { triggeredKeys.append(key) }
}

private final class SpyState: StateHandler {
    let name: String
    let clipKey: String
    let loopsClip: Bool
    private(set) var enterCallCount = 0
    private(set) var exitCallCount = 0
    private(set) var lastUpdateDt: TimeInterval?

    init(name: String, clipKey: String, loopsClip: Bool = false) {
        self.name = name
        self.clipKey = clipKey
        self.loopsClip = loopsClip
    }

    func enter() { enterCallCount += 1 }
    func update(dt: TimeInterval) { lastUpdateDt = dt }
    func exit() { exitCallCount += 1 }
}

final class StateTransitionTests: XCTestCase {
    func test_init_playsInitialStateClipAndTriggersSFXAndEnters() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle", loopsClip: true)

        _ = CharacterController(initialState: idle, avatar: avatar, sfxPlayer: sfx)

        XCTAssertEqual(avatar.playedClips.map(\.clip), ["idle"])
        XCTAssertEqual(avatar.playedClips.map(\.loop), [true])
        XCTAssertEqual(sfx.triggeredKeys, ["idle"]) // clipKey, not the capitalized state name
        XCTAssertEqual(idle.enterCallCount, 1)
    }

    func test_transition_exitsOldState_entersNewState_playsNewClip() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle", loopsClip: true)
        let walk = SpyState(name: "Walk", clipKey: "walk", loopsClip: true)
        let controller = CharacterController(initialState: idle, avatar: avatar, sfxPlayer: sfx)

        controller.transition(to: walk)

        XCTAssertEqual(idle.exitCallCount, 1)
        XCTAssertEqual(walk.enterCallCount, 1)
        XCTAssertEqual(avatar.playedClips.map(\.clip), ["idle", "walk"])
        XCTAssertEqual(sfx.triggeredKeys, ["idle", "walk"])
        XCTAssertTrue(controller.currentState === walk)
    }

    func test_transition_toSameState_isNoOp() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, avatar: avatar, sfxPlayer: sfx)

        controller.transition(to: idle)

        XCTAssertEqual(idle.exitCallCount, 0)
        XCTAssertEqual(idle.enterCallCount, 1) // only the initial enter
        XCTAssertEqual(avatar.playedClips.count, 1)
    }

    func test_update_forwardsDtToCurrentState() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, avatar: avatar, sfxPlayer: sfx)

        controller.update(dt: 0.016)

        XCTAssertEqual(idle.lastUpdateDt, 0.016)
    }
}

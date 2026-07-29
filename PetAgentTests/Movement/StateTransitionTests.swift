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
    private(set) var bounceCalls: [(clip: String, elapsed: TimeInterval)] = []

    func play(clip: String, loop: Bool) { playedClips.append((clip, loop)) }
    func stop() { stopCallCount += 1 }
    func setScreenPosition(_ position: CGPoint) {}
    func setFacing(_ facing: AvatarFacing) {}
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double) {
        bounceCalls.append((clip, elapsed))
    }
}

final class SpySFXTriggering: SFXTriggering {
    private(set) var triggeredKeys: [String] = []
    private(set) var triggeredCalls: [(key: String, loop: Bool)] = []
    func trigger(_ key: String, loop: Bool) {
        triggeredKeys.append(key)
        triggeredCalls.append((key, loop))
    }
}

private final class SpyState: StateHandler {
    let name: String
    let clipKey: String
    let loopsClip: Bool
    let restartsOnReentry: Bool
    private(set) var enterCallCount = 0
    private(set) var exitCallCount = 0
    private(set) var lastUpdateDt: TimeInterval?

    init(name: String, clipKey: String, loopsClip: Bool = false, restartsOnReentry: Bool = false) {
        self.name = name
        self.clipKey = clipKey
        self.loopsClip = loopsClip
        self.restartsOnReentry = restartsOnReentry
    }

    func enter() { enterCallCount += 1 }
    func update(dt: TimeInterval, context: StateContext) { lastUpdateDt = dt }
    func exit() { exitCallCount += 1 }
}

final class StateTransitionTests: XCTestCase {
    func test_init_playsInitialStateClipAndTriggersSFXAndEnters() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle", loopsClip: true)

        _ = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        XCTAssertEqual(avatar.playedClips.map(\.clip), ["idle"])
        XCTAssertEqual(avatar.playedClips.map(\.loop), [true])
        XCTAssertEqual(sfx.triggeredKeys, ["idle"]) // clipKey, not the capitalized state name
        XCTAssertEqual(idle.enterCallCount, 1)
    }

    func test_sfxTrigger_receivesTheStatesLoopsClipFlag() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let reactClick = SpyState(name: "ReactClick", clipKey: "react_click", loopsClip: false)

        _ = CharacterController(initialState: reactClick, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        XCTAssertEqual(sfx.triggeredCalls.map(\.key), ["react_click"])
        XCTAssertEqual(sfx.triggeredCalls.map(\.loop), [false])
    }

    func test_transition_exitsOldState_entersNewState_playsNewClip() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle", loopsClip: true)
        let walk = SpyState(name: "Walk", clipKey: "walk", loopsClip: true)
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.transition(to: walk)

        XCTAssertEqual(idle.exitCallCount, 1)
        XCTAssertEqual(walk.enterCallCount, 1)
        XCTAssertEqual(avatar.playedClips.map(\.clip), ["idle", "walk"])
        XCTAssertEqual(sfx.triggeredKeys, ["idle", "walk"])
        XCTAssertTrue(controller.currentState === walk)
    }

    /// Any state can be interrupted by any other (a click, a drag, an agent
    /// command) -- if the pet gets grabbed mid-ceiling-crawl, only
    /// CeilingState itself asks to stay upside-down; every other state must
    /// come back right-side-up on entry, not just Fall's own reset (which
    /// never runs at all when Ceiling is interrupted directly into ReactDrag).
    func test_transitioningAwayFromCeiling_resetsUpsideDown() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let body = CharacterBody(avatar: avatar, position: .zero)
        let ceiling = CeilingState(durationProvider: { 100 })
        let dragState = SpyState(name: "ReactDrag", clipKey: "react_drag", loopsClip: true)
        let controller = CharacterController(initialState: ceiling, body: body, sfxPlayer: sfx)
        body.isUpsideDown = true // as if CeilingState.update() had already flipped it

        controller.transition(to: dragState)

        XCTAssertFalse(body.isUpsideDown)
    }

    /// A StateKind case added later without updating the registration list
    /// (AppDelegate's `register(_:as:)` calls) would otherwise silently
    /// strand the pet with zero diagnostic. Behavior (a harmless no-op) is
    /// unchanged; this only pins that it stays harmless and documents it.
    func test_transition_toKind_withNothingRegistered_isANoOp() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.transition(to: .walk) // never registered in this test

        XCTAssertTrue(controller.currentState === idle)
    }

    func test_transition_toSameState_isNoOp() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.transition(to: idle)

        XCTAssertEqual(idle.exitCallCount, 0)
        XCTAssertEqual(idle.enterCallCount, 1) // only the initial enter
        XCTAssertEqual(avatar.playedClips.count, 1)
    }

    /// ReactClickState's own doc comment says clicking the pet again while
    /// already reacting replays the reaction rather than being ignored --
    /// the same-state no-op guard above must not swallow this case.
    func test_transition_toSameState_restartsWhenStateOptsIn() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let reactClick = SpyState(name: "ReactClick", clipKey: "react_click", restartsOnReentry: true)
        let controller = CharacterController(initialState: reactClick, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.transition(to: reactClick)

        XCTAssertEqual(reactClick.exitCallCount, 1)
        XCTAssertEqual(reactClick.enterCallCount, 2) // initial + restart
        XCTAssertEqual(avatar.playedClips.count, 2, "should replay the clip too")
    }

    func test_update_forwardsDtToCurrentState() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.update(dt: 0.016)

        XCTAssertEqual(idle.lastUpdateDt, 0.016)
    }

    // MARK: - Bounce motion (2026-07-29 2D switch)

    func test_update_callsUpdateBounce_withCurrentClipAndElapsedTime() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.update(dt: 0.1)

        XCTAssertEqual(avatar.bounceCalls.map(\.clip), ["idle"])
        XCTAssertEqual(avatar.bounceCalls.map(\.elapsed), [0.1])
    }

    func test_update_accumulatesElapsedTimeAcrossMultipleFrames() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.update(dt: 0.1)
        controller.update(dt: 0.1)

        XCTAssertEqual(avatar.bounceCalls.map(\.elapsed), [0.1, 0.2])
    }

    func test_transition_resetsElapsedTimeForTheNewState() {
        let avatar = SpyAvatarPlayable()
        let sfx = SpySFXTriggering()
        let idle = SpyState(name: "Idle", clipKey: "idle")
        let walk = SpyState(name: "Walk", clipKey: "walk")
        let controller = CharacterController(initialState: idle, body: CharacterBody(avatar: avatar, position: .zero), sfxPlayer: sfx)

        controller.update(dt: 0.5) // elapsed builds up in Idle
        controller.transition(to: walk)
        controller.update(dt: 0.1) // should start fresh in Walk, not carry 0.5 over

        XCTAssertEqual(avatar.bounceCalls.map(\.clip), ["idle", "walk"])
        XCTAssertEqual(avatar.bounceCalls.map(\.elapsed), [0.5, 0.1])
    }
}

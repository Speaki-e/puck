//
//  CharacterController.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Drives update(dt) every frame; runs and transitions the current StateHandler.
//

import Foundation

/// The minimal interface F5 (Audio/SFXPlayer) will implement. Kept here so the
/// FSM doesn't need to know about the concrete SFX implementation.
protocol SFXTriggering: AnyObject {
    /// Triggers the sound mapped to an FSM clip key or socket event name key
    /// (silent if the manifest's sounds table has no match). `loop` mirrors
    /// AvatarPlayable.play(clip:loop:) — a looping trigger (e.g. "walk")
    /// keeps playing until a *different* loop key is triggered, at which
    /// point F5 fades the old one out (02_pet-app.md F5: "루프 사운드(walk)는
    /// 상태 유지 중 반복, exit()에서 페이드아웃"). One-shot (loop: false)
    /// triggers (react_click, task_success, ...) never interrupt a loop.
    func trigger(_ key: String, loop: Bool)
}

/// Drives and transitions the current StateHandler. On every state entry,
/// AvatarPlayable.play and SFXTriggering.trigger are always called together
/// from the same spot (enterCurrentState) — 02_pet-app.md F3's shared "enter()" requirement.
final class CharacterController {
    private(set) var currentState: StateHandler
    private let avatar: AvatarPlayable
    private let sfxPlayer: SFXTriggering

    init(initialState: StateHandler, avatar: AvatarPlayable, sfxPlayer: SFXTriggering) {
        self.currentState = initialState
        self.avatar = avatar
        self.sfxPlayer = sfxPlayer
        enterCurrentState()
    }

    /// Allows transitioning from any state to any state (tools/events/PTT/click
    /// can all interrupt at any time — see the section 3 transition table).
    func transition(to newState: StateHandler) {
        guard newState !== currentState else { return }
        currentState.exit()
        currentState = newState
        enterCurrentState()
    }

    func update(dt: TimeInterval) {
        currentState.update(dt: dt)
    }

    private func enterCurrentState() {
        avatar.play(clip: currentState.clipKey, loop: currentState.loopsClip)
        // Use clipKey (e.g. "walk"), not name (e.g. "Walk") — the manifest sounds
        // table is keyed by lowercase clip/event names (protocol section 6), so
        // triggering with the capitalized FSM state name would never match.
        sfxPlayer.trigger(currentState.clipKey, loop: currentState.loopsClip)
        currentState.enter()
    }
}

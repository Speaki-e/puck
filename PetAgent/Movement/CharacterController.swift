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
    /// Triggers the sound mapped to an FSM state name or socket event name key
    /// (silent if the manifest's sounds table has no match).
    func trigger(_ key: String)
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
        sfxPlayer.trigger(currentState.clipKey)
        currentState.enter()
    }
}

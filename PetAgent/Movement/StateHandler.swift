//
//  StateHandler.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  protocol: enter() / update(dt) / exit()
//

import Foundation

/// A single FSM state. name/clipKey correspond to the state transition table
/// in plan/02_pet-app.md section 3 and the avatar manifest's clips keys.
/// On transition, CharacterController calls AvatarPlayable.play AND triggers
/// SFX using clipKey (not name) -- the manifest's sounds table is keyed by
/// the same lowercase clip names as clips, not the capitalized state name.
protocol StateHandler: AnyObject {
    /// FSM state name (e.g. "Idle", "WalkOnTop") -- display/debugging only.
    var name: String { get }
    /// Lookup key into the avatar manifest's clips. States without a dedicated
    /// clip (WalkOnTop, MoveTo) reuse "walk".
    var clipKey: String { get }
    /// Whether the clip can loop (start/end pose match) — idle/walk/climb/type/listen/point etc.
    var loopsClip: Bool { get }

    func enter()
    func update(dt: TimeInterval)
    func exit()
}

extension StateHandler {
    var loopsClip: Bool { false }
    func enter() {}
    func update(dt: TimeInterval) {}
    func exit() {}
}

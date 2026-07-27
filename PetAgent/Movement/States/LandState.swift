//
//  LandState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  Land state's StateHandler implementation
//
//  A brief landing beat so the non-looping land clip is legible, then Idle
//  (plan/02_pet-app.md section 3: "Fall | 착지면 감지 | Land → Idle").
//

import Foundation

final class LandState: StateHandler {
    let name = "Land"
    let clipKey = "land"
    let loopsClip = false

    /// Long enough to read as a landing, short enough not to feel stuck.
    static let duration: TimeInterval = 0.35

    private var elapsed: TimeInterval = 0
    private var hasRequestedIdle = false

    func enter() {
        elapsed = 0
        hasRequestedIdle = false
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedIdle else { return }
        elapsed += dt
        guard elapsed >= Self.duration else { return }
        hasRequestedIdle = true
        context.requestTransition(.idle)
    }
}

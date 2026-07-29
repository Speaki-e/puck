//
//  PettingState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Petting state's StateHandler implementation.
//
//  A double-tap "petting" reaction, distinct from a single ReactClick tap --
//  byeolki's request for more diverse motions/interactions (2026-07-29).
//  Reuses ReactClickState's exact shape (short reaction, then back to
//  whatever the pet was doing), just with its own clip/bounce/emotion so it
//  reads as a different, happier reaction than a plain click.
//

import Foundation

final class PettingState: StateHandler {
    let name = "Petting"
    let clipKey = "pet"
    let loopsClip = false
    // Petting the pet again while it's still reacting should replay the
    // reaction, same reasoning as ReactClickState.restartsOnReentry.
    let restartsOnReentry = true

    /// Long enough for the wiggle bounce to read (BouncePreset.wiggle's own
    /// duration).
    static let duration: TimeInterval = 0.8

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

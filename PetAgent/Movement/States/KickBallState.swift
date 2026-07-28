//
//  KickBallState.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  KickBall state's StateHandler implementation (optional ball-toy
//  interaction, 02_pet-app.md F12).
//
//  A short "header" reaction once the pet has arrived at the ball, then back
//  to Idle -- mirrors ReactClickState's timer shape. `onEnter` is where
//  AppDelegate actually launches the ball (BallPhysics.kick), matching
//  PointState.onEnter's pattern for bootstrap-owned side effects a pure
//  StateHandler shouldn't reach for itself.

import Foundation

final class KickBallState: StateHandler {
    let name = "KickBall"
    let clipKey = "kick" // falls back to react_click, then idle, if the manifest has no dedicated clip
    let loopsClip = false

    /// Long enough for BouncePreset's kick anticipation+impact motion to read.
    static let duration: TimeInterval = 0.4

    /// Fired once, on entry -- AppDelegate uses this to actually launch the
    /// ball (BallPhysics.kick) in the pet's current facing direction.
    var onEnter: (() -> Void)?

    private var elapsed: TimeInterval = 0
    private var hasRequestedIdle = false

    func enter() {
        elapsed = 0
        hasRequestedIdle = false
        onEnter?()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedIdle else { return }
        elapsed += dt
        guard elapsed >= Self.duration else { return }
        hasRequestedIdle = true
        context.requestTransition(.idle)
    }
}

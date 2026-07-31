//
//  IdleFrameRatePolicy.swift
//  Shaydi
//
//  F1 · owner: 강상우 (Sangwoo Kang)
//  Decides when the frame loop may slow down.
//
//  plan/02_pet-app.md F1: "Idle 30초 지속 시 프레임레이트 60→15 다운시프트".
//  FrameClock could already change rate; nothing ever decided when to.
//
//  Two things this does NOT fix, measured rather than assumed:
//
//  1. It does not lower CPU. A resting pet holds ~31%, and `sample` puts
//     essentially all of it in ARView.commonRenderCallback() — RealityKit
//     renders on its own display-linked loop regardless of how often the FSM
//     ticks, and an FSM update is nearly free by comparison. Cutting the
//     renderer means throttling or parking the ARView itself, which the plan
//     does not describe and this does not attempt.
//  2. It rarely even engages. F3's wander timer fires every 8-30s, so the pet
//     almost never stays in Idle for 30 consecutive seconds.
//
//  Kept because the rule is in the plan and the decision layer is what any
//  real fix would need anyway — but nobody should read it as "CPU handled".
//

import Foundation

struct IdleFrameRatePolicy {
    /// How long the pet must have been idle before slowing down.
    let threshold: TimeInterval

    private var idleElapsed: TimeInterval = 0

    init(threshold: TimeInterval = 30) {
        self.threshold = threshold
    }

    /// - Parameter idle: whether the FSM is currently in a resting state.
    /// - Returns: the rate the clock should run at this frame.
    mutating func framesPerSecond(idle: Bool, dt: TimeInterval) -> Double {
        guard idle else {
            // Back to full speed immediately — ramping up a second later
            // would show as a stutter exactly when something is happening.
            idleElapsed = 0
            return FrameClock.activeFramesPerSecond
        }
        idleElapsed += dt
        return idleElapsed >= threshold ? FrameClock.idleFramesPerSecond : FrameClock.activeFramesPerSecond
    }
}

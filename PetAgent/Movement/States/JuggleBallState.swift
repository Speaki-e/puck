//
//  JuggleBallState.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  JuggleBall state's StateHandler implementation (optional ball-toy
//  interaction, 02_pet-app.md F12).
//
//  A couple of small pops before the final kick-away -- more motion variety
//  for the same interaction byeolki cited as the example (2026-07-29:
//  "좀 더 다양한 모션과 상호작용(축구공, 등등)을 추가해줘"). Sits between
//  ChaseBall arriving and KickBall in "Idle/Walk 한정 | 공 던지기(F12) |
//  ChaseBall → JuggleBall → KickBall → Idle".
//
//  All bounces happen within ONE entry rather than re-entering itself per
//  bounce -- re-entering the same StateHandler instance needs
//  restartsOnReentry plus a way to tell "fresh start" apart from "continuing
//  the count," which an internal timer sidesteps entirely.

import Foundation

final class JuggleBallState: StateHandler {
    let name = "JuggleBall"
    let clipKey = "kick" // reuses kick's bounce/clip -- a header-like pop, no dedicated clip in the manifest
    let loopsClip = false

    /// Time between each pop.
    static let bounceInterval: TimeInterval = 0.4
    /// Total pops before handing off to KickBall (including the one on entry).
    static let bounceCount = 2

    /// Fired once per pop, including immediately on entry -- AppDelegate uses
    /// this to actually pop the ball (BallController.juggle()).
    var onBounce: (() -> Void)?

    private var elapsed: TimeInterval = 0
    private var bouncesDone = 0
    private var hasRequestedKick = false

    func enter() {
        elapsed = 0
        hasRequestedKick = false
        bouncesDone = 1
        onBounce?()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedKick else { return }
        elapsed += dt
        guard elapsed >= Self.bounceInterval else { return }
        elapsed = 0

        if bouncesDone < Self.bounceCount {
            bouncesDone += 1
            onBounce?()
        } else {
            hasRequestedKick = true
            context.requestTransition(.kickBall)
        }
    }
}

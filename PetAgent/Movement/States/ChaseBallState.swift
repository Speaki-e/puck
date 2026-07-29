//
//  ChaseBallState.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  ChaseBall state's StateHandler implementation (optional ball-toy
//  interaction, 02_pet-app.md F12).
//
//  "Idle/Walk 한정 | 공 던지기(F12) | ChaseBall → JuggleBall → KickBall → Idle"
//  (plan/02_pet-app.md section 3; JuggleBall added 2026-07-29). Mirrors
//  MoveToState almost exactly --
//  ignores windows in the way for the same reason MoveTo does: the pet is
//  headed somewhere specific (the ball), not wandering.

import CoreGraphics
import Foundation

final class ChaseBallState: StateHandler {
    let name = "ChaseBall"
    let clipKey = "walk" // no dedicated clip in the manifest
    let loopsClip = true

    /// Where the ball landed, in the pet's coordinate space.
    var target: CGPoint?

    private var hasHandedOver = false

    func enter() {
        hasHandedOver = false
    }

    func exit() {
        target = nil // clear so a stale order can't be replayed on the next entry
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasHandedOver else { return }

        guard let target else {
            handOver(.idle, context)
            return
        }

        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }

        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            handOver(.juggleBall, context)
        }
    }

    private func handOver(_ kind: StateKind, _ context: StateContext) {
        hasHandedOver = true
        context.requestTransition(kind)
    }
}

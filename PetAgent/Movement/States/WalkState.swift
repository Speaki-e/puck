//
//  WalkState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Walk state's StateHandler implementation.
//
//  Carries the pet to `target` at constant speed and hands back to Idle on
//  arrival (plan/02_pet-app.md section 3). Whoever transitions into Walk sets
//  the target first — Idle's wander does so via IdleWanderDelegate.
//
//  TODO(P3): detect touching a window's left/right edge -> Climb. Needs the
//  F4 window list plumbed into StateContext.

import CoreGraphics
import Foundation

final class WalkState: StateHandler {
    let name = "Walk"
    let clipKey = "walk"
    let loopsClip = true

    /// Where to walk, in GlobalScreenSpace pixels. Cleared on exit so a stale
    /// destination can't be re-walked next time Walk is entered.
    var target: CGPoint?

    private var hasRequestedIdle = false

    func enter() {
        hasRequestedIdle = false
    }

    func exit() {
        target = nil
    }

    func update(dt: TimeInterval, context: StateContext) {
        // One arrival, one request: the transition only lands after this
        // update returns, so further frames would queue duplicates.
        guard !hasRequestedIdle else { return }

        guard let target else {
            // Nothing to walk to — looping the walk clip on the spot would
            // read as the pet moonwalking.
            requestIdle(context)
            return
        }

        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }

        let step = MovementSolver.step(from: context.body.position, toward: target, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            requestIdle(context)
        }
    }

    private func requestIdle(_ context: StateContext) {
        hasRequestedIdle = true
        context.requestTransition(.idle)
    }
}

//
//  ClimbState.swift
//  Shaydi
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Climb state's StateHandler implementation.
//
//  Rides a window's side up to its top edge, then walks along it
//  (plan/02_pet-app.md section 3: "Climb | 창 상단 도달 | WalkOnTop").
//

import CoreGraphics
import Foundation

final class ClimbState: StateHandler {
    let name = "Climb"
    let clipKey = "climb"
    let loopsClip = true

    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }

        guard let window = WindowSupport.windowBeingClimbed(at: context.body.position, in: context.windows) else {
            // The window went away mid-climb — there is nothing to hold on to.
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        // Straight up: no facing change, or the character flips partway up.
        let target = CGPoint(x: context.body.position.x, y: window.frame.minY)
        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            oneShot.fire(.walkOnTop, using: context.requestTransition)
        }
    }
}

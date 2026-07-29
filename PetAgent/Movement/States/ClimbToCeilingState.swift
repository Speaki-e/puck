//
//  ClimbToCeilingState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  ClimbToCeiling state's StateHandler implementation.
//
//  F3 ceiling-crawling (2026-07-29): climbs straight up to the roamable
//  area's top edge, independent of any window (unlike ClimbState, which
//  rides a window's side) -- WanderScheduler's .climbToCeiling outcome can
//  fire from anywhere the pet happens to be standing.
//

import CoreGraphics
import Foundation

final class ClimbToCeilingState: StateHandler {
    let name = "ClimbToCeiling"
    let clipKey = "climb"
    let loopsClip = true

    private var hasRequestedTransition = false

    func enter() {
        hasRequestedTransition = false
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedTransition else { return }

        // Straight up: x stays fixed, same "no facing change mid-climb" rule
        // ClimbState uses. The target is roamableArea.minY + avatarHeight,
        // NOT roamableArea.minY itself -- position is still the feet here
        // (right-side-up, body extending upward), so climbing feet all the
        // way to the literal top of the screen would push the head off-screen
        // before "arrival." Stopping with the head just touching the ceiling
        // also makes this land on exactly the same rendered rect CeilingState
        // computes for position.y == roamableArea.minY once it flips upside
        // down, so the flip reads as an in-place turn, not a jump.
        let target = CGPoint(x: context.body.position.x, y: context.roamableArea.minY + context.avatarHeight)
        let step = MovementSolver.step(from: context.body.position, toward: target, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            hasRequestedTransition = true
            context.requestTransition(.ceiling)
        }
    }
}

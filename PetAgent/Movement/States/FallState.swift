//
//  FallState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Fall state's StateHandler implementation.
//
//  The only state with acceleration (plan/02_pet-app.md F3: "물리엔진 없음 …
//  Fall만 낙하 가속도"). The surface comes from StateContext.landingY, which
//  F4's LandingSurfaceResolver answers with a window top edge or the floor.
//

import CoreGraphics
import Foundation

final class FallState: StateHandler {
    let name = "Fall"
    let clipKey = "fall"
    let loopsClip = false

    private var velocity: CGFloat = 0
    private var hasLanded = false

    func enter() {
        // From rest every time: carrying the previous fall's velocity would
        // make a second fall start at whatever speed the first ended with.
        velocity = 0
        hasLanded = false
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasLanded else { return }

        let step = MovementSolver.fallStep(
            position: context.body.position,
            velocity: velocity,
            dt: dt,
            landingY: context.landingY(context.body.position)
        )
        context.body.position = step.position
        velocity = step.velocity

        if step.hasLanded {
            hasLanded = true
            context.requestTransition(.land)
        }
    }
}

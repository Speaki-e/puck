//
//  BallPhysics.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  Pure physics for the ball-toy interaction (02_pet-app.md F12, optional,
//  lowest priority). The drop reuses MovementSolver.fallStep's free-fall
//  arithmetic directly rather than reimplementing it; the kicked-away fling
//  is the one bit of new motion this file adds.
//
//  Kept free of any rendering/window/FSM concerns so the arithmetic is
//  testable on its own -- BallController (or whatever drives it per frame)
//  only decides *when* to call this and what to render.
//

import CoreGraphics
import Foundation

enum BallPhase: Equatable {
    /// Dropped and still falling toward a landing surface.
    case falling
    /// Landed, waiting for the pet to kick it.
    case resting
    /// Kicked away -- flying off under gravity until its lifetime elapses or
    /// it exits the roamable area.
    case kicked
    /// Done -- nothing left to render or simulate.
    case gone
}

struct BallState: Equatable {
    var position: CGPoint
    var verticalVelocity: CGFloat = 0
    var horizontalVelocity: CGFloat = 0
    var phase: BallPhase = .falling
    /// Seconds since entering `.kicked` -- only used to decide when a kicked
    /// ball counts as "gone" (no landing/window tracking for the fling itself).
    var kickedElapsed: TimeInterval = 0
}

enum BallPhysics {
    static let gravity = MovementSolver.gravity
    /// A kicked ball flying longer than this is considered gone, regardless
    /// of where it ended up -- a decorative fling doesn't need to be tracked
    /// forever.
    static let kickedLifetime: TimeInterval = 1.2
    /// How far outside roamableArea still counts as "worth simulating" before
    /// a kicked ball is considered gone.
    static let outOfBoundsMargin: CGFloat = 200

    static func step(_ state: BallState, dt: TimeInterval, landingY: CGFloat, roamableArea: CGRect) -> BallState {
        switch state.phase {
        case .falling:
            let fall = MovementSolver.fallStep(
                position: state.position,
                velocity: state.verticalVelocity,
                dt: dt,
                landingY: landingY
            )
            var next = state
            next.position = fall.position
            next.verticalVelocity = fall.velocity
            next.phase = fall.hasLanded ? .resting : .falling
            return next

        case .resting:
            return state // waits for kick(_:direction:) to move it into .kicked

        case .kicked:
            let newVerticalVelocity = state.verticalVelocity + gravity * CGFloat(dt)
            let newPosition = CGPoint(
                x: state.position.x + state.horizontalVelocity * CGFloat(dt),
                y: state.position.y + newVerticalVelocity * CGFloat(dt)
            )
            var next = state
            next.position = newPosition
            next.verticalVelocity = newVerticalVelocity
            next.kickedElapsed = state.kickedElapsed + dt

            let outOfBounds = !roamableArea.insetBy(dx: -outOfBoundsMargin, dy: -outOfBoundsMargin).contains(newPosition)
            next.phase = (next.kickedElapsed >= kickedLifetime || outOfBounds) ? .gone : .kicked
            return next

        case .gone:
            return state
        }
    }

    /// Pops a resting ball straight up, back into `.falling` -- it arcs back
    /// down and lands (`.resting`) the same way a drop does, since a
    /// negative (upward) initial velocity just decelerates under gravity,
    /// peaks, and falls back via the exact same math (2026-07-29, more
    /// interaction variety: a juggle before the final kick-away).
    static func juggle(_ state: BallState, liftSpeed: CGFloat = 260) -> BallState {
        var next = state
        next.phase = .falling
        next.verticalVelocity = -liftSpeed
        next.horizontalVelocity = 0
        return next
    }

    /// Launches a resting ball up and in the pet's facing direction, so the
    /// "header" visually reads as sending it forward rather than straight up.
    static func kick(
        _ state: BallState,
        direction: AvatarFacing,
        horizontalSpeed: CGFloat = 260,
        liftSpeed: CGFloat = 420
    ) -> BallState {
        var next = state
        next.phase = .kicked
        next.kickedElapsed = 0
        next.horizontalVelocity = direction == .right ? horizontalSpeed : -horizontalSpeed
        next.verticalVelocity = -liftSpeed // negative = upward (Y increases downward)
        return next
    }
}

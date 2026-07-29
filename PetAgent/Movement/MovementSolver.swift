//
//  MovementSolver.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Pure motion arithmetic for MoveTo/Walk/Fall.
//
//  plan/02_pet-app.md F3: "물리엔진 없음. MoveTo 등속(px/sec) + 도착 반경,
//  Fall만 낙하 가속도". Kept free of any entity/state so the arithmetic is
//  testable on its own — the states below it only decide *when* to call this.
//
//  All positions are GlobalScreenSpace pixels: top-left origin, Y increasing
//  downward. Gravity therefore adds to Y.
//

import CoreGraphics
import Foundation

enum MovementSolver {
    /// Default walking speed, px/sec.
    static let walkSpeed: CGFloat = 90
    /// Default gravity, px/sec².
    static let gravity: CGFloat = 1200
    /// Default terminal velocity, px/sec. A fall from the ceiling covers the
    /// whole screen's height, far more than any window-edge fall ever did --
    /// unbounded acceleration over that distance eventually moves the pet
    /// dozens of pixels in a single frame, reading as a teleport rather than
    /// a fall.
    static let terminalVelocity: CGFloat = 900
    /// How close counts as "there".
    static let arrivalRadius: CGFloat = 2

    struct Step: Equatable {
        let position: CGPoint
        let hasArrived: Bool
    }

    struct FallStep: Equatable {
        let position: CGPoint
        let velocity: CGFloat
        let hasLanded: Bool
    }

    /// One constant-velocity frame toward `target`.
    ///
    /// The travelled distance is clamped to the remaining distance: at high
    /// speed or after a long frame the pet would otherwise fly past the target
    /// and oscillate around it, never landing inside `arrivalRadius`.
    static func step(
        from position: CGPoint,
        toward target: CGPoint,
        speed: CGFloat = walkSpeed,
        dt: TimeInterval,
        arrivalRadius: CGFloat = arrivalRadius
    ) -> Step {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = hypot(dx, dy)

        guard distance > arrivalRadius else {
            return Step(position: position, hasArrived: true)
        }

        let travel = speed * CGFloat(dt)
        guard travel < distance else {
            return Step(position: target, hasArrived: true)
        }

        // Normalize so diagonal motion isn't 1.41x faster than axis-aligned.
        let moved = CGPoint(x: position.x + dx / distance * travel, y: position.y + dy / distance * travel)
        return Step(position: moved, hasArrived: false)
    }

    /// Which way the character should face to head toward `target`, or nil for
    /// purely vertical motion (climbing must not flip it).
    static func facing(from position: CGPoint, toward target: CGPoint) -> AvatarFacing? {
        let dx = target.x - position.x
        guard dx != 0 else { return nil }
        return dx > 0 ? .right : .left
    }

    /// One accelerating frame of free fall. `landingY` stops the pet on a
    /// surface instead of sinking through it when a frame overshoots.
    static func fallStep(
        position: CGPoint,
        velocity: CGFloat,
        gravity: CGFloat = gravity,
        dt: TimeInterval,
        landingY: CGFloat? = nil,
        terminalVelocity: CGFloat = terminalVelocity
    ) -> FallStep {
        let newVelocity = min(velocity + gravity * CGFloat(dt), terminalVelocity)
        let newY = position.y + newVelocity * CGFloat(dt)

        if let landingY, newY >= landingY {
            return FallStep(position: CGPoint(x: position.x, y: landingY), velocity: 0, hasLanded: true)
        }
        return FallStep(position: CGPoint(x: position.x, y: newY), velocity: newVelocity, hasLanded: false)
    }
}

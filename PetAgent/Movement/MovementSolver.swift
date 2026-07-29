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
    /// Default gravity, px/sec². High enough that even a short fall (off a
    /// window's top edge) picks up real speed within roughly a window's
    /// height, instead of staying floaty for the whole drop the way a gentler
    /// value does over so short a distance.
    ///
    static let gravity: CGFloat = 2400
    /// The speed a fall settles at, px/sec — what air resistance does to a
    /// real falling object, and the reason a dropped ball reads as descending
    /// steadily rather than ever faster (byeolki: "진짜 공 던지는것 처럼 쭉
    /// 일정하게 떨어지게", 2026-07-29).
    ///
    /// Uncapped, the pet spends the last quarter of a long drop moving 35px a
    /// frame, which reads as it being yanked onto the floor rather than
    /// landing on it. The pairing matters: gravity stays high so a short fall
    /// off a window edge still gets up to speed within its own height, and
    /// this keeps a long fall from running away past that same speed.
    static let terminalVelocity: CGFloat = 1200
    /// How close counts as "there".
    static let arrivalRadius: CGFloat = 2
    /// Fastest the pet can be thrown, px/sec (byeolki: "드래그해서 던지면
    /// 던져지게", 2026-07-29). A flick of the wrist can move the cursor
    /// several thousand px/sec, which would fire the pet off the far edge of
    /// the screen before the eye can follow it; this crosses a display in
    /// roughly half a second, which still reads as a hard throw.
    static let maxThrowSpeed: CGFloat = 2500
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

    /// One accelerating frame of free fall, settling at `terminalVelocity`.
    /// `landingY` stops the pet on a surface instead of sinking through it
    /// when a frame overshoots.
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

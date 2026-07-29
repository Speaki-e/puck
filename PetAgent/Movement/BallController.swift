//
//  BallController.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  Glue between BallPhysics (pure math) and the CALayer it's drawn on
//  (02_pet-app.md F12, optional ball-toy interaction).
//
//  The ball is a pet-app-bundled decoration, not a user-customizable avatar
//  asset (plan/02_pet-app.md F12) -- drawn as a plain circle so no art asset
//  is needed at all.

import AppKit
import CoreGraphics
import Foundation
import QuartzCore

final class BallController {
    /// Fired once when the ball transitions from falling to resting. The
    /// Idle/Walk-only gate on actually chasing it (F3's priority rule) is the
    /// caller's decision, not this controller's.
    var onLanded: ((CGPoint) -> Void)?

    let layer = CALayer()
    private(set) var state: BallState?

    var isActive: Bool { state != nil }

    init(parent: CALayer, radius: CGFloat = 14) {
        layer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        layer.cornerRadius = radius
        layer.backgroundColor = NSColor.white.cgColor
        layer.borderColor = NSColor.black.cgColor
        layer.borderWidth = 1.5
        layer.isHidden = true
        // Ticked every frame like the pet is, so the same rule applies: no
        // implicit animation between the frames we compute.
        layer.disableImplicitAnimations()
        parent.addSublayer(layer)
    }

    func spawn(at position: CGPoint) {
        state = BallState(position: position, phase: .falling)
        layer.position = position
        layer.isHidden = false
    }

    /// Call every frame while a ball exists (falling, resting, or kicked).
    func tick(dt: TimeInterval, landingY: CGFloat, roamableArea: CGRect) {
        guard let current = state else { return }
        let wasFalling = current.phase == .falling

        let next = BallPhysics.step(current, dt: dt, landingY: landingY, roamableArea: roamableArea)
        state = next
        layer.position = next.position

        if wasFalling, next.phase == .resting {
            onLanded?(next.position)
        }
        if next.phase == .gone {
            layer.isHidden = true
            state = nil
        }
    }

    /// Launches a resting ball away in `direction` -- a no-op if it's still
    /// falling or already kicked, so a stray call can't relaunch it mid-flight.
    func kick(direction: AvatarFacing) {
        guard let current = state, current.phase == .resting else { return }
        state = BallPhysics.kick(current, direction: direction)
    }

    /// Pops a resting ball straight up -- a no-op if it's still falling or
    /// already kicked, same guard as kick(direction:). Used for the
    /// juggle-before-kick variety (2026-07-29).
    func juggle() {
        guard let current = state, current.phase == .resting else { return }
        state = BallPhysics.juggle(current)
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change -- mirrors SpriteAvatar.reparent's precedent.
    func reparent(to newParent: CALayer) {
        layer.removeFromSuperlayer()
        newParent.addSublayer(layer)
    }
}

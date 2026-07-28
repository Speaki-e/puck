//
//  WalkOnTopState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  WalkOnTop state's StateHandler implementation
//
//  Strolls along a window's top edge until the window stops being there —
//  closed, minimized, or simply walked off the end of. Both are the same
//  situation: nothing underfoot (plan/02_pet-app.md section 3: "WalkOnTop |
//  지지 창 소멸/최소화 | Fall").
//
//  Reuses the "walk" clip; the manifest has no dedicated one.

import CoreGraphics
import Foundation

final class WalkOnTopState: StateHandler {
    let name = "WalkOnTop"
    let clipKey = "walk"
    let loopsClip = true

    /// Resolved on the first update() after enter() -- Climb always arrives
    /// at whichever edge is nearer the approach direction (WalkState.swift
    /// walks up to a window's left edge approaching from the left, right
    /// edge approaching from the right), so walking a hardcoded direction
    /// from there could walk straight back off the very edge just climbed.
    private var direction: CGFloat?
    private var hasRequestedFall = false

    func enter() {
        hasRequestedFall = false
        direction = nil
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedFall else { return }

        guard let window = WindowSupport.supportingWindow(under: context.body.position, in: context.windows) else {
            hasRequestedFall = true
            context.requestTransition(.fall)
            return
        }

        let resolvedDirection = direction ?? Self.initialDirection(position: context.body.position, windowFrame: window.frame)
        direction = resolvedDirection

        let nextX = context.body.position.x + resolvedDirection * MovementSolver.walkSpeed * CGFloat(dt)
        context.body.facing = resolvedDirection > 0 ? .right : .left
        context.body.position = CGPoint(x: nextX, y: window.frame.minY)
    }

    /// Walk into the window from whichever edge is nearer, not off the side
    /// just climbed.
    private static func initialDirection(position: CGPoint, windowFrame: CGRect) -> CGFloat {
        let distanceToLeftEdge = abs(position.x - windowFrame.minX)
        let distanceToRightEdge = abs(position.x - windowFrame.maxX)
        return distanceToLeftEdge <= distanceToRightEdge ? 1 : -1
    }
}

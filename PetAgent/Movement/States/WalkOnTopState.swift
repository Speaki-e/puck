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

    private var direction: CGFloat = 1
    private var hasRequestedFall = false

    func enter() {
        hasRequestedFall = false
        direction = 1
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedFall else { return }

        guard let window = WindowSupport.supportingWindow(under: context.body.position, in: context.windows) else {
            hasRequestedFall = true
            context.requestTransition(.fall)
            return
        }

        let nextX = context.body.position.x + direction * MovementSolver.walkSpeed * CGFloat(dt)
        context.body.facing = direction > 0 ? .right : .left
        context.body.position = CGPoint(x: nextX, y: window.frame.minY)
    }
}

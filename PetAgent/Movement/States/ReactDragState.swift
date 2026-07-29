//
//  ReactDragState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  ReactDrag state's StateHandler implementation.
//
//  The pet hangs off the cursor while being dragged and drops when let go
//  ("임의 | 캐릭터 드래그/드롭 | ReactDrag(커서 추종) → Fall",
//  plan/02_pet-app.md section 3). Eases toward the cursor (MovementSolver.ease)
//  rather than snapping to it outright -- byeolki reported the drag still felt
//  unnatural ("아직 움직임이 부자연스러워") with an exact 1:1 follow, which
//  reads as a rigid teleport rather than something being carried. The ease
//  rate is fast enough to stay responsive, not laggy.
//

import CoreGraphics
import Foundation

final class ReactDragState: StateHandler {
    let name = "ReactDrag"
    let clipKey = "react_drag"
    let loopsClip = true

    /// Where the cursor is, in the pet's coordinate space. Updated by whoever
    /// owns the mouse monitor; nil means it hasn't moved since the grab.
    var cursorPosition: CGPoint?

    private var isReleased = false
    private var hasRequestedFall = false

    func enter() {
        isReleased = false
        hasRequestedFall = false
        cursorPosition = nil
    }

    /// The mouse came up — stop following and let go on the next frame.
    func release() {
        isReleased = true
    }

    func update(dt: TimeInterval, context: StateContext) {
        if isReleased {
            guard !hasRequestedFall else { return }
            hasRequestedFall = true
            // Dropped where it was let go, not wherever the cursor went next.
            context.requestTransition(.fall)
            return
        }

        guard let cursorPosition else { return }
        if let facing = MovementSolver.facing(from: context.body.position, toward: cursorPosition) {
            context.body.facing = facing
        }
        context.body.position = MovementSolver.ease(from: context.body.position, toward: cursorPosition, dt: dt)
    }
}

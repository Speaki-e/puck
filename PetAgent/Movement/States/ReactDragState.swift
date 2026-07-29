//
//  ReactDragState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  ReactDrag state's StateHandler implementation.
//
//  The pet hangs off the cursor while being dragged and drops when let go
//  ("임의 | 캐릭터 드래그/드롭 | ReactDrag(커서 추종) → Fall",
//  plan/02_pet-app.md section 3).
//
//  While held, the pet is **not moving** — it is being carried (byeolki:
//  "이동한다는 개념이 아니라 잡고 끌려간다는 개념", 2026-07-29). So this state
//  runs no locomotion at all: no easing, no speed, no MovementSolver. The pet
//  is rigidly attached to the cursor and its position is assigned outright,
//  exactly like dragging a window ("구글 창 같은걸 드래그 할때처럼"). Every
//  earlier version -- eased follow, then a speed-capped follow -- had the pet
//  travelling toward the cursor under its own power, which is what made a fast
//  drag read as the pet chasing the hand instead of being in it.
//
//  The grab offset is captured on the first frame and held for the whole drag,
//  so whatever point you grabbed stays under the cursor and grabbing the pet
//  never jumps it.
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

    /// How quickly the smoothed cursor velocity forgets older frames, 1/sec.
    /// Roughly an 80ms window: long enough that one stuttering frame can't
    /// decide the throw, short enough that only the final flick counts and
    /// not the leisurely dragging that came before it.
    private static let velocitySmoothingRate: CGFloat = 12

    private var isReleased = false
    private var hasRequestedFall = false
    /// Where the pet sat relative to the cursor when it was grabbed. Held for
    /// the whole drag so the grabbed point stays under the cursor.
    private var grabOffset: CGPoint?
    /// Smoothed cursor velocity, px/sec — the throw's speed if released now.
    private var cursorVelocity: CGPoint = .zero
    private var previousCursorPosition: CGPoint?

    func enter() {
        isReleased = false
        hasRequestedFall = false
        cursorPosition = nil
        grabOffset = nil
        cursorVelocity = .zero
        previousCursorPosition = nil
    }

    /// The mouse came up — stop following and let go on the next frame.
    func release() {
        isReleased = true
    }

    func update(dt: TimeInterval, context: StateContext) {
        if isReleased {
            guard !hasRequestedFall else { return }
            hasRequestedFall = true
            // Hand the throw to Fall. Let go of a still cursor and this is
            // zero, i.e. the plain straight-down drop it always was.
            context.body.launchVelocity = MovementSolver.cappedThrow(cursorVelocity)
            // Dropped where it was let go, not wherever the cursor went next.
            context.requestTransition(.fall)
            return
        }

        guard let cursorPosition else { return }
        trackCursorVelocity(to: cursorPosition, dt: dt)

        // First frame of the grab: remember where the pet sat relative to the
        // cursor and don't move it at all, so grabbing never jumps it.
        guard let grabOffset else {
            grabOffset = CGPoint(x: context.body.position.x - cursorPosition.x, y: context.body.position.y - cursorPosition.y)
            return
        }

        let target = CGPoint(x: cursorPosition.x + grabOffset.x, y: cursorPosition.y + grabOffset.y)
        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }
        // Assigned outright, with no speed of its own: while held, the pet is
        // part of the cursor rather than something travelling toward it.
        context.body.position = target
    }

    /// Exponential moving average of the cursor's velocity. Frame deltas on
    /// their own are far too jumpy to throw with -- the cursor routinely
    /// stalls for a frame mid-drag, and releasing on one of those would drop
    /// the pet straight down after an obvious hard flick.
    private func trackCursorVelocity(to cursorPosition: CGPoint, dt: TimeInterval) {
        defer { previousCursorPosition = cursorPosition }
        guard let previousCursorPosition, dt > 0 else { return }

        let sample = CGPoint(
            x: (cursorPosition.x - previousCursorPosition.x) / CGFloat(dt),
            y: (cursorPosition.y - previousCursorPosition.y) / CGFloat(dt)
        )
        let weight = 1 - exp(-Self.velocitySmoothingRate * CGFloat(dt))
        cursorVelocity = CGPoint(
            x: cursorVelocity.x + (sample.x - cursorVelocity.x) * weight,
            y: cursorVelocity.y + (sample.y - cursorVelocity.y) * weight
        )
    }
}

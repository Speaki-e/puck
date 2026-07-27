//
//  ReactClickState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  ReactClick state's StateHandler implementation.
//
//  A short reaction to being clicked, then back to whatever the pet was doing
//  ("임의 | 캐릭터 클릭 | ReactClick → Idle", plan/02_pet-app.md section 3).
//  Also reused as the failure reaction for tool_result(ok=false) — see
//  EventRouter.
//

import Foundation

final class ReactClickState: StateHandler {
    let name = "ReactClick"
    let clipKey = "react_click"
    let loopsClip = false

    /// Long enough for the non-looping clip to read.
    static let duration: TimeInterval = 0.6

    private var elapsed: TimeInterval = 0
    private var hasRequestedIdle = false

    func enter() {
        // Restart on re-entry: clicking the pet again replays the reaction
        // rather than inheriting the previous one's remaining time.
        elapsed = 0
        hasRequestedIdle = false
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedIdle else { return }
        elapsed += dt
        guard elapsed >= Self.duration else { return }
        hasRequestedIdle = true
        context.requestTransition(.idle)
    }
}

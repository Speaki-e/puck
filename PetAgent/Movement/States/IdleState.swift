//
//  IdleState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Idle state's StateHandler implementation.
//

import Foundation

/// IdleState does not decide which state to actually transition to when the
/// WanderScheduler timer fires — that decision needs the window list (F4,
/// e.g. finding the nearest window), so it's delegated up to whatever owns
/// CharacterController (the future App bootstrap wiring).
protocol IdleWanderDelegate: AnyObject {
    func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome)
}

final class IdleState: StateHandler {
    let name = "Idle"
    let clipKey = "idle"
    let loopsClip = true

    weak var wanderDelegate: IdleWanderDelegate?
    private let scheduler: WanderScheduler

    init(scheduler: WanderScheduler = WanderScheduler()) {
        self.scheduler = scheduler
    }

    func update(dt: TimeInterval, context: StateContext) {
        if let outcome = scheduler.tick(dt: dt) {
            wanderDelegate?.idleStateDidRequestWander(outcome)
        }
    }
}

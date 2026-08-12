//
//  IdleState.swift
//  Puck
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
        // WalkOnTopState already re-checks its supporting window every frame;
        // Idle never did, so a pet resting after Fall -> Land -> Idle (window
        // tops are valid landing surfaces, see LandingSurfaceResolver) stayed
        // floating in place forever if that window later closed/minimized.
        // landingY(position) > position.y means a gap has opened up below --
        // whatever was there is now gone.
        let surfaceY = context.landingY(context.body.position)
        guard surfaceY <= context.body.position.y + WindowSupport.footTolerance else {
            context.requestTransition(.fall)
            return
        }

        if let outcome = scheduler.tick(dt: dt) {
            wanderDelegate?.idleStateDidRequestWander(outcome)
        }
    }
}

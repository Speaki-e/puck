//
//  WanderScheduler.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Idle's 8-30s random wander timer, weighted next-action selection.
//

import Foundation

/// The wander timer owned by IdleState. Accumulates dt; once the timer
/// expires, draws and returns the next Outcome, then draws its own next
/// interval. Randomness is injectable so tests can verify it deterministically.
final class WanderScheduler {
    enum Outcome: Equatable {
        /// Move to a random point (Walk)
        case walkToRandomPoint
        /// Move to and climb the nearest window (Climb)
        case climbNearestWindow
        /// Climb straight up to the ceiling and crawl there (F3 ceiling-crawling, 2026-07-29)
        case climbToCeiling
        /// Stay idle this round
        case stay
    }

    private var elapsed: TimeInterval = 0
    private var nextFireInterval: TimeInterval
    private let nextIntervalProvider: () -> TimeInterval
    private let outcomeProvider: () -> Outcome

    init(
        nextIntervalProvider: @escaping () -> TimeInterval = { TimeInterval.random(in: 8...30) },
        outcomeProvider: @escaping () -> Outcome = WanderScheduler.weightedRandomOutcome
    ) {
        self.nextIntervalProvider = nextIntervalProvider
        self.outcomeProvider = outcomeProvider
        self.nextFireInterval = nextIntervalProvider()
    }

    /// Accumulates dt. Once elapsed time passes the timer, returns an Outcome
    /// and resets the timer + draws the next interval.
    @discardableResult
    func tick(dt: TimeInterval) -> Outcome? {
        elapsed += dt
        guard elapsed >= nextFireInterval else { return nil }
        elapsed = 0
        nextFireInterval = nextIntervalProvider()
        return outcomeProvider()
    }

    /// Default weights: 45% random move, 25% climb nearest window, 15%
    /// climb to the ceiling, 15% stay (first-pass values, tunable later).
    static func weightedRandomOutcome() -> Outcome {
        switch Double.random(in: 0..<1) {
        case ..<0.45: return .walkToRandomPoint
        case ..<0.70: return .climbNearestWindow
        case ..<0.85: return .climbToCeiling
        default: return .stay
        }
    }
}

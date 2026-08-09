//
//  WanderScheduler.swift
//  Puck
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Idle's 8-30s random wander timer, weighted next-action selection.
//

import Foundation

/// The wander timer owned by IdleState. Accumulates dt; once the timer
/// expires, draws and returns the next Outcome, then draws its own next
/// interval. Randomness is injectable so tests can verify it deterministically.
final class WanderScheduler {
    enum Outcome: Hashable {
        /// Move to a random point (Walk)
        case walkToRandomPoint
        /// Move to and climb the nearest window (Climb)
        case climbNearestWindow
        /// Climb straight up to the ceiling and crawl there (F3 ceiling-crawling, 2026-07-29)
        case climbToCeiling
        /// Go and play with a toy that is lying about (F12 multi-toy, 2026-07-30).
        /// Without this draw, play could only ever start at the moment a toy
        /// LANDED -- so a toy the pet had already kicked away and walked off
        /// from was abandoned for good, and with several toys out that was the
        /// normal case rather than an edge one.
        case playWithToy
        /// Stay idle this round
        case stay
    }

    /// How long Idle waits before drawing its next Outcome.
    ///
    /// 02_pet-app.md F3 specified `8...30`, and both ends of that were wrong
    /// in practice, in opposite directions:
    ///
    /// - 30s at the top read as broken rather than calm. Measured, the pet
    ///   walked a few seconds and then froze for over 20, which looks like its
    ///   motion is stuttering to a halt.
    /// - A flat 5s (tried next) overcorrected: sampling the frame loop showed
    ///   the pet in motion on essentially every frame of every window, and one
    ///   `.climbToCeiling` draw chains ~12s of climb plus ceiling plus fall on
    ///   top of that, so it effectively never rested.
    ///
    /// 8...15 keeps it visibly alive without it being in constant motion. It
    /// stays a *range* because a fixed interval makes the pet metronomic --
    /// the one thing a wander timer exists to avoid.
    ///
    /// Note this is the wait between *draws*, not between moves: 15% of draws
    /// come back `.stay`, so some observed rests span two intervals.
    static let defaultIntervalRange: ClosedRange<TimeInterval> = 8...15

    private var elapsed: TimeInterval = 0
    private var nextFireInterval: TimeInterval
    private let nextIntervalProvider: () -> TimeInterval
    private let outcomeProvider: () -> Outcome

    init(
        nextIntervalProvider: @escaping () -> TimeInterval = { .random(in: WanderScheduler.defaultIntervalRange) },
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

    /// Default weights: 35% random move, 25% climb nearest window, 15% climb
    /// to the ceiling, 10% play with a toy, 15% stay.
    ///
    /// The toy draw was taken out of walking's share rather than out of the
    /// climbs: walking is the filler behaviour, and it is also what the pet
    /// falls back to when the draw can't be honoured (no toy is out, nothing
    /// to climb), so borrowing from it doesn't change how often the pet ends
    /// up walking as much as the numbers suggest.
    static func weightedRandomOutcome() -> Outcome {
        switch Double.random(in: 0..<1) {
        case ..<0.35: return .walkToRandomPoint
        case ..<0.60: return .climbNearestWindow
        case ..<0.75: return .climbToCeiling
        case ..<0.85: return .playWithToy
        default: return .stay
        }
    }
}

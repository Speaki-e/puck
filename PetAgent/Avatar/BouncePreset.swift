//
//  BouncePreset.swift
//  PetAgent
//
//  F2 · owner: 박해영 (Haeyoung Park)
//  Procedural squash-and-stretch "bounce" motion for 2D sprite avatars
//  (02_pet-app.md F2, 2026-07-29 2D switch).
//
//  A static illustration ships no animation frames, so instead of playing
//  back baked motion, pet-app computes a small scale transform every frame
//  from (which clip is playing, how long it's been playing, a 0...1 global
//  intensity dial) -- pure math, no timers or rendering here.
//

import Foundation

/// A scale-only transform (no position offset -- squash-and-stretch on scale
/// alone already reads as "bounce" without needing a separate bob offset).
struct BounceTransform: Equatable {
    let scaleX: Double
    let scaleY: Double

    static let identity = BounceTransform(scaleX: 1, scaleY: 1)
}

enum BouncePreset: Equatable {
    case none
    case idle
    case walk
    case land
    /// point/react_click's short "pop" pulse.
    case pop
    case kick

    /// Which preset a clip name uses. Clips with no bounce behavior (climb,
    /// fall, type, listen, react_drag, and anything unrecognized) get `.none`.
    static func preset(for clip: String) -> BouncePreset {
        switch clip {
        case "idle": return .idle
        case "walk": return .walk
        case "land": return .land
        case "point", "react_click": return .pop
        case "kick": return .kick
        default: return .none
        }
    }

    /// `elapsed`: seconds since the current clip started playing.
    /// `intensity`: the manifest's `bounce_intensity` (0...1, 0 = fully static).
    func transform(elapsed: TimeInterval, intensity: Double) -> BounceTransform {
        guard intensity > 0 else { return .identity }

        switch self {
        case .none:
            return .identity

        case .idle:
            // Slow breathing bob.
            let period = 2.5
            let phase = sin(2 * .pi * elapsed / period)
            let amplitude = 0.04 * intensity
            return BounceTransform(scaleX: 1, scaleY: 1 + amplitude * phase)

        case .walk:
            // Faster bounce synced to a nominal step cadence, with a slight
            // horizontal squeeze at the peak so it doesn't just look like
            // pure vertical scaling. The squeeze uses phase^2 rather than
            // abs(phase) -- abs() folds sharply (a derivative kink) at every
            // zero-crossing, which reads as the motion "catching" at each
            // footfall; squaring keeps the same 0-at-rest/full-at-peak shape
            // but eases through zero instead.
            let period = 0.35
            let phase = sin(2 * .pi * elapsed / period)
            let amplitude = 0.08 * intensity
            return BounceTransform(scaleX: 1 - amplitude * 0.3 * phase * phase, scaleY: 1 + amplitude * phase)

        case .land:
            // Decaying spring: squashed flat on impact, oscillates back to
            // identity. exp(...) alone would decay monotonically with no
            // spring-back overshoot; multiplying by cos(...) gives it a
            // couple of damped oscillations before settling.
            let duration = 0.35
            let t = elapsed / duration
            let squash = intensity * exp(-t * 6) * cos(t * 12)
            return BounceTransform(scaleX: 1 + squash * 0.3, scaleY: 1 - squash * 0.3)

        case .pop:
            // One pulse: 0 -> peak -> back to identity, then holds.
            let duration = 0.25
            let t = min(elapsed / duration, 1)
            let pop = intensity * sin(t * .pi)
            return BounceTransform(scaleX: 1 + pop * 0.15, scaleY: 1 + pop * 0.15)

        case .kick:
            // Two phases: anticipation squash (first 40% of the window), then
            // an impact stretch the opposite way. Each phase is its own
            // sine bump (0 -> peak -> 0) rather than a linear ramp, so both
            // ease in/out AND meet at identity at the phase boundary --
            // linear ramps peak right at the boundary and jump straight to
            // the other phase's peak, a visible snap mid-kick.
            let duration = 0.4
            let t = min(elapsed / duration, 1)
            let anticipationWindow = 0.4
            if t < anticipationWindow {
                let localT = t / anticipationWindow
                let s = intensity * sin(localT * .pi)
                return BounceTransform(scaleX: 1 + s * 0.2, scaleY: 1 - s * 0.2)
            } else {
                let localT = (t - anticipationWindow) / (1 - anticipationWindow)
                let s = intensity * sin(localT * .pi)
                return BounceTransform(scaleX: 1 - s * 0.2, scaleY: 1 + s * 0.3)
            }
        }
    }
}

//
//  WindowSupport.swift
//  Puck
//
//  F3/F4 · owner: 박해영 (Haeyoung Park)
//  Which window, if any, the pet is standing on or bumping into.
//
//  Pure lookups over the F4 window list so the states above stay free of
//  geometry. Everything is in the pet's coordinate space: overlay-local
//  pixels, top-left origin, Y down — so a window's top edge is frame.minY.
//

import CoreGraphics

enum WindowSupport {
    /// How close to a top edge still counts as standing on it.
    static let footTolerance: CGFloat = 4
    /// How close to a side counts as bumping into it.
    static let edgeTolerance: CGFloat = 4

    /// The frontmost window whose top edge the pet is standing on.
    static func supportingWindow(under position: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { window in
            position.x >= window.frame.minX
                && position.x <= window.frame.maxX
                && abs(position.y - window.frame.minY) <= footTolerance
        }
    }

    /// The frontmost window the pet is pressed against the side of, and whose
    /// body it would otherwise walk through.
    static func windowBeingClimbed(at position: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { window in
            (abs(position.x - window.frame.minX) <= edgeTolerance
                || abs(position.x - window.frame.maxX) <= edgeTolerance)
                && position.y >= window.frame.minY
                && position.y <= window.frame.maxY
        }
    }

    /// Windows the pet could actually climb from `position`: at the pet's
    /// height, and with enough headroom above (`roamableTop`/`avatarHeight`)
    /// that climbing wouldn't clip its head off the top of the screen.
    /// Shared by `nearestClimbTarget` and `blockingWindow`, which used to
    /// duplicate this exact two-stage filter (found via review).
    private static func climbableWindows(
        at position: CGPoint,
        in windows: [WindowInfo],
        roamableTop: CGFloat,
        avatarHeight: CGFloat
    ) -> [WindowInfo] {
        windows
            .filter { window in
                position.y >= window.frame.minY && position.y <= window.frame.maxY
            }
            .filter { window in
                window.frame.minY - roamableTop >= avatarHeight
            }
    }

    /// A point to walk to that will put the pet against the nearest climbable
    /// window's side, so `blockingWindow` picks it up and Walk hands off to
    /// Climb -- the pet spends too much time glued to the floor otherwise,
    /// and should climb up windows now and then.
    ///
    /// The wander scheduler's `.climbNearestWindow` outcome had never been
    /// implemented -- it fell through to a plain random walk -- so a quarter
    /// of every wander decision quietly kept the pet on the floor, and the
    /// only climbs that ever happened were the accidental ones where a random
    /// walk target happened to lie past a window edge.
    ///
    /// Returns nil when nothing nearby can be climbed, which the caller
    /// should treat as "wander normally" rather than as an error.
    static func nearestClimbTarget(
        from position: CGPoint,
        in windows: [WindowInfo],
        roamableTop: CGFloat = -.greatestFiniteMagnitude,
        avatarHeight: CGFloat = 0
    ) -> CGPoint? {
        // How far past the edge to aim. Walking *to* the edge exactly leaves
        // the pet a rounding error short of it on some frames, and the climb
        // never triggers.
        let overshoot: CGFloat = 4

        let edges = climbableWindows(at: position, in: windows, roamableTop: roamableTop, avatarHeight: avatarHeight)
            .flatMap { [$0.frame.minX, $0.frame.maxX] }
            // Already standing at this edge: pick a different one rather than
            // walking a zero-length path and re-deciding a moment later.
            .filter { abs($0 - position.x) > edgeTolerance }

        guard let nearest = edges.min(by: { abs($0 - position.x) < abs($1 - position.x) }) else { return nil }

        return CGPoint(
            x: nearest > position.x ? nearest + overshoot : nearest - overshoot,
            y: position.y
        )
    }

    /// The window edge a pet walking from `position` toward `target` runs into
    /// first, if any — the trigger for Walk -> Climb.
    ///
    /// `roamableTop`/`avatarHeight` (F3, 2026-07-29): a window whose top edge
    /// doesn't leave a full avatar height of headroom above it (a
    /// near-fullscreen or maximized window) is excluded rather than climbed --
    /// climbing it would clip the character's head off the top of the screen,
    /// the same geometry problem ceiling-crawling had. Defaults keep every
    /// existing caller's behavior unchanged unless they opt in.
    static func blockingWindow(
        walkingFrom position: CGPoint,
        toward target: CGPoint,
        in windows: [WindowInfo],
        roamableTop: CGFloat = -.greatestFiniteMagnitude,
        avatarHeight: CGFloat = 0
    ) -> WindowInfo? {
        let goingRight = target.x > position.x
        return climbableWindows(at: position, in: windows, roamableTop: roamableTop, avatarHeight: avatarHeight)
            .filter { window in
                let edge = goingRight ? window.frame.minX : window.frame.maxX
                return goingRight ? (edge > position.x && edge <= target.x) : (edge < position.x && edge >= target.x)
            }
            .min { a, b in
                let edgeA = goingRight ? a.frame.minX : a.frame.maxX
                let edgeB = goingRight ? b.frame.minX : b.frame.maxX
                return goingRight ? edgeA < edgeB : edgeA > edgeB
            }
    }
}

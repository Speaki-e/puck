//
//  WindowSupport.swift
//  PetAgent
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

    /// The window edge a pet walking from `position` toward `target` runs into
    /// first, if any — the trigger for Walk -> Climb.
    static func blockingWindow(walkingFrom position: CGPoint, toward target: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        let goingRight = target.x > position.x
        return windows
            .filter { window in
                // Must be at the pet's height to be in the way at all.
                position.y >= window.frame.minY && position.y <= window.frame.maxY
            }
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

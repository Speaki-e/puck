//
//  LandingSurfaceResolver.swift
//  PetAgent
//
//  F4 · owner: Haeyoung Park
//  Resolves the landing surface (window top edge) accounting for Z-order/overlap
//

import CoreGraphics

/// Resolves what the pet lands on while falling straight down at a given x.
/// Landing surfaces are window top edges or, failing that, the screen bottom
/// (Dock top is an optional surface not handled here yet).
enum LandingSurfaceResolver {
    /// - Parameters:
    ///   - x: character's x-coordinate, in GlobalScreenSpace's normalized space.
    ///   - currentY: character's current y — only surfaces at or below this
    ///     (i.e. not yet passed while falling) are considered.
    ///   - windows: layer-0 windows in front-to-back Z order (index 0 = frontmost).
    ///   - screenBottomY: fallback surface if no window qualifies.
    static func landingY(
        atX x: CGFloat,
        fallingFromY currentY: CGFloat,
        windows: [WindowInfo],
        screenBottomY: CGFloat
    ) -> CGFloat {
        let candidates = windows.indices.compactMap { index -> CGFloat? in
            let window = windows[index]
            guard window.frame.minX <= x, x <= window.frame.maxX else { return nil }

            let topEdgeY = window.frame.minY
            guard topEdgeY >= currentY else { return nil }

            let isOccluded = windows[..<index].contains { front in
                front.frame.minX <= x && x <= front.frame.maxX
                    && front.frame.minY <= topEdgeY && topEdgeY <= front.frame.maxY
            }
            return isOccluded ? nil : topEdgeY
        }

        return candidates.min() ?? screenBottomY
    }
}

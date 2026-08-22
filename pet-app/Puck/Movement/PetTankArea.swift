//
//  PetTankArea.swift
//  Puck
//
//  The tank as the movement engine wants it: a roamableArea in the overlay
//  window's own coordinates.
//
//  Pure, because the two things that make this fiddly -- rebasing onto an
//  overlay window that is not at Quartz's origin, and refusing a tank the pet
//  cannot stand in -- are both worth testing without a screen.
//

import CoreGraphics

enum PetTankArea {
    /// How much wider than the pet a tank has to be before it is worth
    /// standing in. One pet-width leaves nowhere to walk.
    static let minimumWidthInPets: CGFloat = 2

    /// - Parameters:
    ///   - wire: the tank in Quartz global coordinates, as the client sent it.
    ///   - overlayOriginInQuartz: the overlay window's top-left in the same
    ///     space (AppDelegate computes this from its AppKit frame).
    ///   - overlaySize: the overlay window's size, i.e. what the rect has to
    ///     fit inside to be reachable at all.
    ///   - petSize: the avatar's size *at tank scale*, not its desktop size.
    /// - Returns: nil when the tank is unusable, which means "stay on the
    ///   desktop" -- never a clamped rect, because a pet squeezed into a
    ///   sliver reads as a bug rather than as a pet.
    static func roamableArea(
        fromWire wire: BridgeRect,
        overlayOriginInQuartz: CGPoint,
        overlaySize: CGSize,
        petSize: CGSize
    ) -> CGRect? {
        // CGRect's width/height getters return the *absolute* value of a
        // negative size, so a malformed wire rect would otherwise sail
        // through the size guard below as if it were legitimately large.
        guard wire.width > 0, wire.height > 0 else { return nil }

        let local = CGRect(
            x: CGFloat(wire.x) - overlayOriginInQuartz.x,
            y: CGFloat(wire.y) - overlayOriginInQuartz.y,
            width: CGFloat(wire.width),
            height: CGFloat(wire.height)
        )
        // Clip to what the overlay can actually show before sizing it up --
        // a tank whose far edge hangs off the window (dragged half off
        // screen, or a resize race) is only as roamable as the part that's
        // actually inside.
        let clipped = local.intersection(CGRect(origin: .zero, size: overlaySize))
        guard clipped.width >= petSize.width * minimumWidthInPets, clipped.height >= petSize.height else {
            return nil
        }
        return clipped
    }
}

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
        let local = CGRect(
            x: CGFloat(wire.x) - overlayOriginInQuartz.x,
            y: CGFloat(wire.y) - overlayOriginInQuartz.y,
            width: CGFloat(wire.width),
            height: CGFloat(wire.height)
        )
        guard local.width >= petSize.width * minimumWidthInPets, local.height >= petSize.height else {
            return nil
        }
        guard CGRect(origin: .zero, size: overlaySize).intersects(local) else { return nil }
        return local
    }
}

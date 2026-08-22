//
//  AppDelegate+Tank.swift
//  Puck
//
//  The pet's tank inside the client window (2026-08-22): applying what the
//  client reports, and moving the pet in and out.
//
//  Everything the pet can do follows roamableArea, so going home is one
//  assignment plus a scale -- see docs/superpowers/specs/2026-08-22-pet-tank-design.md
//  for why the rendering stays here rather than moving into PuckClient.
//

import AppKit
import CoreGraphics

extension AppDelegate {
    /// How much smaller the pet is while it is in the tank. A 90pt strip
    /// cannot hold a 120pt pet, and the tank reads as a small glass box.
    /// How tall the pet stands on the island, in points.
    ///
    /// A fixed height, not a fraction of whatever the size slider is set to:
    /// the island is a fixed 90pt whoever is looking at it, so a relative
    /// scale made the pet fill it at one setting and rattle around in it at
    /// another. On the desktop the slider still decides.
    static let tankPetHeight: CGFloat = 72

    /// The client reported its tank. Stores the geometry and hands the
    /// in-or-out question to the decider; nothing moves until `tickPetHome`
    /// says the state has held.
    func applyPetHome(rect: BridgeRect?, visible: Bool, pinned: Bool) {
        petTankArea = rect.flatMap { wire in
            guard let window = primaryWindow, let space = screenManager?.current else { return nil }
            let origin = space.normalized(fromAppKit: CGPoint(x: window.frame.minX, y: window.frame.maxY))
            return PetTankArea.roamableArea(
                fromWire: wire,
                overlayOriginInQuartz: origin,
                overlaySize: groundAwareSize(of: window),
                petSize: CGSize(
                    width: baseHitboxSize.width * self.tankScale,
                    height: baseHitboxSize.height * self.tankScale
                )
            )
        }
        petHomeDecider.isPetHidden = isCharacterHidden
        petHomeDecider.report(hasTank: petTankArea != nil, visible: visible, pinned: pinned)

        // PetHomeDecider only fires on a home<->desktop transition, so a
        // dragged or resized client window while the pet is already home
        // would otherwise never reach roamableArea again. The pet isn't
        // going anywhere -- the room around it moved -- so no fade.
        if let tank = petTankArea, desktopRoamableArea != nil,
           let controller = characterController, let body = characterBody {
            controller.roamableArea = tank
            body.position = ScreenBounds.contain(
                CGPoint(x: body.position.x, y: tank.maxY),
                visualBounds: body.visualBounds,
                in: tank
            )
        }
    }

    /// Called every frame. Does nothing until a reported state has held.
    func tickPetHome(dt: TimeInterval) {
        petHomeDecider.isPetHidden = isCharacterHidden
        switch petHomeDecider.tick(dt: dt) {
        case .home: movePetHome()
        case .desktop: sendPetToDesktop()
        case nil: break
        }
    }

    /// The client went away. The tank went with it, so the pet comes out --
    /// a rect from a process that is gone is not somewhere to live.
    func petHomeConnectionLost() {
        petTankArea = nil
        petHomeDecider.report(hasTank: false, visible: false, pinned: false)
        sendPetToDesktop()
    }

    private func movePetHome() {
        guard let controller = characterController, let tank = petTankArea else { return }
        cancelWander()
        if desktopRoamableArea == nil {
            desktopRoamableArea = controller.roamableArea
            desktopAvatarScale = currentAvatarScale
        }
        carryPet(
            of: controller,
            to: CGPoint(x: tank.midX, y: tank.maxY),
            arrivingIn: tank,
            scale: tankScale
        )
    }

    func sendPetToDesktop() {
        guard let controller = characterController, let desktop = desktopRoamableArea else { return }
        cancelWander()
        desktopRoamableArea = nil
        carryPet(
            of: controller,
            to: CGPoint(x: desktop.midX, y: desktop.maxY),
            arrivingIn: desktop,
            scale: desktopAvatarScale
        )
    }

    /// The scale that puts the pet at `tankPetHeight`, whatever avatar is
    /// loaded. 1 when there is no avatar yet, which only happens before one
    /// is installed and never while a move is running.
    var tankScale: Double {
        guard baseHitboxSize.height > 0 else { return 1 }
        return Double(Self.tankPetHeight / baseHitboxSize.height)
    }

    /// What `applyLiveAvatarScale` was last given, derived rather than stored:
    /// that method sets `avatarHitboxSize = baseHitboxSize * scale`, so the
    /// ratio is the scale. Nothing else keeps it -- the size slider hands a
    /// value straight in and forgets it.
    private var currentAvatarScale: Double {
        guard baseHitboxSize.height > 0 else { return 1 }
        return Double(avatarHitboxSize.height / baseHitboxSize.height)
    }

    /// Carries the pet across, in view the whole way.
    ///
    /// This used to be a cut -- fade out, set the position, fade in -- which
    /// read as the pet vanishing and a copy appearing elsewhere. Both worlds
    /// are rectangles in the same space, so the trip between them is an
    /// ordinary move and there is no reason to hide it.
    ///
    /// The roamable area is widened to cover both ends for the duration.
    /// `update(dt:)` clamps horizontally into it every frame whatever the
    /// state is doing, so leaving it at the world being left would drag the
    /// pet back at the first step out of it. TravelState hands it back on
    /// arrival, before anything else runs.
    ///
    /// The size travels with it, on the same eased curve. It used to change
    /// on arrival, which read as the pet landing and then being resized --
    /// two events where there is one.
    private func carryPet(
        of controller: CharacterController,
        to destination: CGPoint,
        arrivingIn area: CGRect,
        scale: Double
    ) {
        guard let body = characterBody else { return }
        let departingScale = currentAvatarScale
        travelState.origin = body.position
        travelState.destination = destination
        // Sized along the way rather than on landing. Snapping at the end
        // reads as the pet arriving and *then* being resized, which is two
        // events where the eye expects one -- and going the other way it
        // popped to full size the instant it touched the desktop.
        travelState.onProgress = { [weak self] progress in
            self?.applyLiveAvatarScale(departingScale + (scale - departingScale) * progress)
        }
        travelState.onArrival = { controller.roamableArea = area }
        controller.roamableArea = controller.roamableArea.union(area)
        controller.transition(to: .travel)
    }
}

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
    static let tankAvatarScale = 0.6

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
                    width: baseHitboxSize.width * Self.tankAvatarScale,
                    height: baseHitboxSize.height * Self.tankAvatarScale
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
        // Nothing on screen may change before the fade has hidden the pet --
        // update(dt:) clamps into roamableArea every frame regardless of
        // state, so a scale or bounds change applied here would show up as a
        // snap at full opacity before the fade even starts.
        fadePetAcross {
            self.applyLiveAvatarScale(self.desktopAvatarScale * Self.tankAvatarScale)
            controller.roamableArea = tank
            self.characterBody?.position = CGPoint(x: tank.midX, y: tank.maxY)
            controller.transition(to: .land)
        }
    }

    func sendPetToDesktop() {
        guard let controller = characterController, let desktop = desktopRoamableArea else { return }
        cancelWander()
        desktopRoamableArea = nil
        fadePetAcross {
            self.applyLiveAvatarScale(self.desktopAvatarScale)
            controller.roamableArea = desktop
            self.characterBody?.position = CGPoint(x: desktop.midX, y: desktop.maxY)
            controller.transition(to: .land)
        }
    }

    /// What `applyLiveAvatarScale` was last given, derived rather than stored:
    /// that method sets `avatarHitboxSize = baseHitboxSize * scale`, so the
    /// ratio is the scale. Nothing else keeps it -- the size slider hands a
    /// value straight in and forgets it.
    private var currentAvatarScale: Double {
        guard baseHitboxSize.height > 0 else { return 1 }
        return Double(avatarHitboxSize.height / baseHitboxSize.height)
    }

    /// Out at one end, in at the other. Walking between the two would have to
    /// cross a coordinate space the pet does not live in, and reads as the pet
    /// clipping through the window frame.
    private func fadePetAcross(_ move: @escaping () -> Void) {
        avatar?.setAlpha(0, duration: 0.2) { [weak self] in
            move()
            self?.avatar?.setAlpha(1, duration: 0.2, completion: nil)
        }
    }
}

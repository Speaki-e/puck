//
//  AvatarPlayable.swift
//  PetAgent
//
//  F2 · owner: 강상우 (Sangwoo Kang)
//  protocol: play(clip:loop:) / stop / setScreenPosition / setFacing
//
//  The FSM (Movement/CharacterController) only knows this protocol — it has no
//  idea whether USDZAvatar/VideoAvatar/SpriteAvatar is actually playing
//  (02_pet-app.md F2).

import CoreGraphics
import Foundation

enum AvatarFacing {
    case left
    case right
}

protocol AvatarPlayable: AnyObject {
    func play(clip: String, loop: Bool)
    func stop()
    func setScreenPosition(_ position: CGPoint)
    func setFacing(_ facing: AvatarFacing)

    /// Per-frame procedural "bounce" motion (2026-07-29 2D switch, 02_pet-app.md
    /// F2) -- `clip`/`elapsed` describe how long the current clip has been
    /// playing, `intensity` is the manifest's bounce_intensity. Default is a
    /// no-op: usdz/video avatars have no use for this, only SpriteAvatar acts on it.
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double)
}

extension AvatarPlayable {
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double) {}
}

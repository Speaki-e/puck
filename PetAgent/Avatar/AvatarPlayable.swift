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

enum AvatarFacing {
    case left
    case right
}

protocol AvatarPlayable: AnyObject {
    func play(clip: String, loop: Bool)
    func stop()
    func setScreenPosition(_ position: CGPoint)
    func setFacing(_ facing: AvatarFacing)
}

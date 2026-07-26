//
//  AvatarPlayable.swift
//  PetAgent
//
//  F2 · 담당: 강상우
//  protocol: play(clip:loop:) / stop / setScreenPosition / setFacing
//
//  FSM(Movement/CharacterController)은 이 프로토콜만 알고 USDZAvatar/VideoAvatar/SpriteAvatar
//  중 무엇이 실제로 재생 중인지 모른다 (02_pet-app.md F2).

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

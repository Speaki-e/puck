//
//  BallHeadCollision.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  Whether a falling ball's X currently overlaps the character's head, and
//  if so, where it should land -- byeolki: "축구공을 소환하면 캐릭터
//  머리로 떨어져서 통 튀어서 없어지게 해줘". Without this, a thrown ball
//  falls straight through the character to the floor/window below it,
//  since LandingSurfaceResolver only knows about windows, not the pet.
//
//  Pure geometry, no BallController/CharacterBody coupling, so the caller
//  (AppDelegate's frame loop) decides each frame whether the head or the
//  normal floor/window surface is nearer and feeds MovementSolver.fallStep
//  the smaller of the two -- the existing fall/kick physics do the rest
//  unchanged.
//

import CoreGraphics

enum BallHeadCollision {
    /// - Parameters:
    ///   - ballX: the falling ball's current x.
    ///   - characterPosition: the character's ground/feet point.
    ///   - avatarSize: the rendered avatar's current size (hitbox * scale).
    /// - Returns: the head's Y (top of the avatar) if `ballX` is within the
    ///   avatar's horizontal width, else nil -- there's nothing to hit.
    static func landingY(ballX: CGFloat, characterPosition: CGPoint, avatarSize: CGSize) -> CGFloat? {
        guard abs(ballX - characterPosition.x) <= avatarSize.width / 2 else { return nil }
        return characterPosition.y - avatarSize.height
    }
}

//
//  BallHeadCollisionTests.swift
//  PetAgent
//
//  F12 test · owner: 박해영 (Haeyoung Park)
//  byeolki: "축구공을 소환하면 캐릭터 머리로 떨어져서 통 튀어서 없어지게
//  해줘" -- a ball falling near the character should hit its head instead of
//  passing straight through to the floor.
//

import XCTest
@testable import PetAgent

final class BallHeadCollisionTests: XCTestCase {
    private let characterPosition = CGPoint(x: 500, y: 800) // ground/feet point
    private let avatarSize = CGSize(width: 130, height: 140)

    func test_ballDirectlyAboveTheHead_landsAtHeadHeight() {
        let y = BallHeadCollision.landingY(ballX: 500, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertEqual(y, 800 - 140)
    }

    func test_ballWithinHalfTheAvatarWidth_stillHitsTheHead() {
        let y = BallHeadCollision.landingY(ballX: 500 + 64, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertEqual(y, 660)
    }

    func test_ballOutsideTheAvatarWidth_missesEntirely() {
        let y = BallHeadCollision.landingY(ballX: 500 + 200, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertNil(y)
    }

    func test_ballJustOutsideTheHalfWidth_misses() {
        let y = BallHeadCollision.landingY(ballX: 500 + 66, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertNil(y)
    }
}

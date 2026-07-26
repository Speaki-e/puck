//
//  ClickThroughControllerTests.swift
//  PetAgent
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  Pure hitbox hit-test: plan/02_pet-app.md F1 ("커서가 캐릭터 히트박스
//  (manifest hitbox 기준 AABB) 진입 시 false, 이탈 시 복귀").
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class ClickThroughControllerTests: XCTestCase {
    private let characterPosition = CGPoint(x: 500, y: 500)
    private let hitboxSize = CGSize(width: 120, height: 140)

    func test_cursorAtCharacterCenter_allowsClicks() {
        XCTAssertTrue(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: characterPosition,
                characterScreenPosition: characterPosition,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorFarAway_doesNotAllowClicks() {
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: CGPoint(x: 0, y: 0),
                characterScreenPosition: characterPosition,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorJustInsideHitboxEdge_allowsClicks() {
        // Half-width = 60, half-height = 70; just inside the right/bottom edge.
        let justInside = CGPoint(x: characterPosition.x + 59, y: characterPosition.y + 69)
        XCTAssertTrue(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: justInside,
                characterScreenPosition: characterPosition,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorJustOutsideHitboxEdge_doesNotAllowClicks() {
        let justOutside = CGPoint(x: characterPosition.x + 61, y: characterPosition.y + 71)
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: justOutside,
                characterScreenPosition: characterPosition,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_zeroSizeHitbox_neverAllowsClicks() {
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: characterPosition,
                characterScreenPosition: characterPosition,
                hitboxSize: .zero
            )
        )
    }
}

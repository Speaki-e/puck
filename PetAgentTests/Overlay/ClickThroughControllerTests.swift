//
//  ClickThroughControllerTests.swift
//  PetAgent
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  Pure hitbox hit-test: plan/02_pet-app.md F1 ("커서가 캐릭터 히트박스
//  (manifest hitbox 기준 AABB) 진입 시 false, 이탈 시 복귀").
//
//  `characterScreenPosition` is the character's ground/feet point -- the
//  same convention CharacterBody.position/StateContext use everywhere else
//  (WalkState's targets, LandingSurfaceResolver, USDZAvatar's root-at-feet
//  rig). This is AppKit *global* screen space (bottom-left origin, Y
//  increases upward), so the hitbox extends *upward* (toward larger Y) from
//  the ground point, not symmetrically around it -- the previous
//  symmetric-around-point version left the character's upper half outside
//  its own hitbox (byeolki's report: clicking/dragging the pet felt broken
//  after the 2D switch made `characterScreenPosition` unambiguously the feet).
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class ClickThroughControllerTests: XCTestCase {
    private let groundPoint = CGPoint(x: 500, y: 500)
    private let hitboxSize = CGSize(width: 120, height: 140)

    func test_cursorAtTheGroundPoint_allowsClicks() {
        XCTAssertTrue(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: groundPoint,
                characterScreenPosition: groundPoint,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorAboveTheGroundPoint_withinHitboxHeight_allowsClicks() {
        // The character's upper body/head, not just its feet -- this is
        // exactly what the symmetric-around-point version missed.
        let nearHead = CGPoint(x: groundPoint.x, y: groundPoint.y + 130)
        XCTAssertTrue(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: nearHead,
                characterScreenPosition: groundPoint,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorBelowTheGroundPoint_doesNotAllowClicks() {
        // Below the character's feet -- there's nothing there to click.
        let belowFeet = CGPoint(x: groundPoint.x, y: groundPoint.y - 1)
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: belowFeet,
                characterScreenPosition: groundPoint,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorFarAway_doesNotAllowClicks() {
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: CGPoint(x: 0, y: 0),
                characterScreenPosition: groundPoint,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorJustInsideHitboxEdges_allowsClicks() {
        // Half-width = 60 either side of x; full height = 140 above the ground point.
        let justInside = CGPoint(x: groundPoint.x + 59, y: groundPoint.y + 139)
        XCTAssertTrue(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: justInside,
                characterScreenPosition: groundPoint,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_cursorJustOutsideHitboxEdges_doesNotAllowClicks() {
        let justOutside = CGPoint(x: groundPoint.x + 61, y: groundPoint.y + 141)
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: justOutside,
                characterScreenPosition: groundPoint,
                hitboxSize: hitboxSize
            )
        )
    }

    func test_zeroSizeHitbox_neverAllowsClicks() {
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: groundPoint,
                characterScreenPosition: groundPoint,
                hitboxSize: .zero
            )
        )
    }

    // MARK: - isUpsideDown (F3 ceiling-crawling, 2026-07-29)

    /// Hanging from the ceiling, the character's body extends DOWNWARD
    /// (toward smaller Y in this AppKit bottom-left-origin space) from the
    /// attachment point -- the same rect the ground case uses, built above
    /// the point instead of below it, makes the visibly-hanging pet
    /// unclickable (byeolki: "애가 잘 안 잡힘" while it was on the ceiling).
    func test_cursorBelowTheCeilingPoint_withinHitboxHeight_allowsClicksWhenUpsideDown() {
        let ceilingPoint = CGPoint(x: 500, y: 900)
        let belowCeiling = CGPoint(x: ceilingPoint.x, y: ceilingPoint.y - 130)
        XCTAssertTrue(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: belowCeiling,
                characterScreenPosition: ceilingPoint,
                hitboxSize: hitboxSize,
                isUpsideDown: true
            )
        )
    }

    func test_cursorAboveTheCeilingPoint_doesNotAllowClicksWhenUpsideDown() {
        let ceilingPoint = CGPoint(x: 500, y: 900)
        let aboveCeiling = CGPoint(x: ceilingPoint.x, y: ceilingPoint.y + 1)
        XCTAssertFalse(
            ClickThroughController.shouldAllowClicks(
                cursorPosition: aboveCeiling,
                characterScreenPosition: ceilingPoint,
                hitboxSize: hitboxSize,
                isUpsideDown: true
            )
        )
    }
}

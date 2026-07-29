//
//  ScreenBoundsTests.swift
//  PetAgent
//
//  F3 test · owner: 박해영 (Haeyoung Park)
//  Keeping the pet on screen and bouncing it off the edges, measured by the
//  artwork's own outline (byeolki: "이거 화면 밖으로 나가지 못하게 해야함 / 이
//  펫 에셋의 태두리를 사각형으로 정확히 잡고 그 태두리 기반으로 화면경계에서
//  튕기게", 2026-07-29).
//

import XCTest
@testable import PetAgent

final class ScreenBoundsTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    /// A 100pt-wide pet standing on its position: 50pt either side, 120 tall.
    private let outline = CGRect(x: -50, y: -120, width: 100, height: 120)

    // MARK: - Containment

    func test_contain_stopsTheOutlineAtTheEdge_notTheCentre() {
        let contained = ScreenBounds.contain(CGPoint(x: 980, y: 400), visualBounds: outline, in: area)

        // 950, not 1000: at 1000 the right half of the pet is off screen.
        XCTAssertEqual(contained.x, 950)
    }

    func test_contain_stopsAtTheLeftEdgeToo() {
        let contained = ScreenBounds.contain(CGPoint(x: 10, y: 400), visualBounds: outline, in: area)

        XCTAssertEqual(contained.x, 50)
    }

    func test_contain_leavesAPositionAlreadyInsideAlone() {
        let contained = ScreenBounds.contain(CGPoint(x: 500, y: 400), visualBounds: outline, in: area)

        XCTAssertEqual(contained, CGPoint(x: 500, y: 400))
    }

    /// The outline is measured from the artwork, so it needn't be centred on
    /// the pet's position -- a character leaning right has more of itself on
    /// one side, and the edge it stops at differs accordingly.
    func test_contain_respectsAnAsymmetricOutline() {
        let leaningRight = CGRect(x: -20, y: -120, width: 100, height: 120)

        let atRight = ScreenBounds.contain(CGPoint(x: 990, y: 0), visualBounds: leaningRight, in: area)
        let atLeft = ScreenBounds.contain(CGPoint(x: 0, y: 0), visualBounds: leaningRight, in: area)

        XCTAssertEqual(atRight.x, 920, "80pt of artwork sits to the right of the position")
        XCTAssertEqual(atLeft.x, 20, "and 20pt to the left")
    }

    func test_contain_neverMovesThePetVertically() {
        let contained = ScreenBounds.contain(CGPoint(x: -500, y: 12_345), visualBounds: outline, in: area)

        XCTAssertEqual(contained.y, 12_345, "vertical placement belongs to landing surfaces")
    }

    // MARK: - Bouncing

    func test_bounce_reversesDirectionAtTheRightEdge() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 960, y: 0), // 10pt past the 950 limit
            velocity: 800,
            visualBounds: outline,
            in: area
        )

        XCTAssertTrue(bounce.didBounce)
        XCTAssertLessThan(bounce.velocity, 0, "heading back the other way")
        XCTAssertEqual(bounce.velocity, -800 * ScreenBounds.restitution, accuracy: 0.001, "having lost energy")
        XCTAssertEqual(bounce.position.x, 940, "reflected back inside by how far it overshot")
    }

    func test_bounce_reversesDirectionAtTheLeftEdge() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 30, y: 0), // 20pt past the 50 limit
            velocity: -600,
            visualBounds: outline,
            in: area
        )

        XCTAssertTrue(bounce.didBounce)
        XCTAssertEqual(bounce.velocity, 600 * ScreenBounds.restitution, accuracy: 0.001)
        XCTAssertEqual(bounce.position.x, 70)
    }

    func test_bounce_leavesAPetInTheMiddleAlone() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 500, y: 0),
            velocity: 800,
            visualBounds: outline,
            in: area
        )

        XCTAssertFalse(bounce.didBounce)
        XCTAssertEqual(bounce.velocity, 800)
        XCTAssertEqual(bounce.position.x, 500)
    }

    /// A slow nudge into the wall should settle against it. Bouncing at any
    /// speed leaves the pet buzzing on the edge in ever-smaller hops.
    func test_bounce_belowTheMinimumSpeed_restsAgainstTheEdge() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 955, y: 0),
            velocity: 40,
            visualBounds: outline,
            in: area
        )

        XCTAssertFalse(bounce.didBounce)
        XCTAssertEqual(bounce.velocity, 0)
        XCTAssertEqual(bounce.position.x, 950, "resting exactly on the limit")
    }

    /// Repeated bounces have to run out of energy rather than continuing
    /// forever.
    func test_bounce_repeated_eventuallySettles() {
        var position = CGPoint(x: 960, y: 0)
        var velocity: CGFloat = 900

        for _ in 0..<20 {
            let bounce = ScreenBounds.bounceHorizontally(
                position: position, velocity: velocity, visualBounds: outline, in: area
            )
            position = bounce.position
            velocity = bounce.velocity
            // Drive it straight back into the same wall each time.
            if velocity != 0 {
                position = CGPoint(x: 960, y: 0)
                velocity = abs(velocity)
            }
        }

        XCTAssertEqual(velocity, 0, "the bouncing dies out")
    }

    // MARK: - Ceiling

    /// byeolki: "위쪽 화면도" — thrown up hard, the pet must come off the top
    /// of the screen instead of leaving it.
    func test_ceiling_bouncesTheHeadOffTheTop() {
        // The outline reaches 120pt above the position, so the head meets
        // y=0 when the position is at 120.
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 110), // 10pt too high
            velocity: -700, // negative = travelling upward
            visualBounds: outline,
            in: area
        )

        XCTAssertTrue(bounce.didBounce)
        XCTAssertGreaterThan(bounce.velocity, 0, "now heading back down")
        XCTAssertEqual(bounce.velocity, 700 * ScreenBounds.restitution, accuracy: 0.001)
        XCTAssertEqual(bounce.position.y, 130, "reflected back down by its overshoot")
    }

    func test_ceiling_ignoresAPetFallingDownward() {
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 110),
            velocity: 400, // falling
            visualBounds: outline,
            in: area
        )

        XCTAssertFalse(bounce.didBounce, "coming down is a landing, not a ceiling hit")
        XCTAssertEqual(bounce.velocity, 400)
    }

    func test_ceiling_ignoresAPetBelowTheCeiling() {
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 400),
            velocity: -700,
            visualBounds: outline,
            in: area
        )

        XCTAssertFalse(bounce.didBounce)
        XCTAssertEqual(bounce.velocity, -700)
    }

    /// A tall avatar's head reaches the ceiling before a short one's, so the
    /// bounce point follows the measured outline rather than the position.
    func test_ceiling_limitFollowsTheOutlineHeight() {
        let tall = CGRect(x: -50, y: -300, width: 100, height: 300)

        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 290),
            velocity: -700,
            visualBounds: tall,
            in: area
        )

        XCTAssertTrue(bounce.didBounce, "a 300pt-tall pet is already at the ceiling at y=290")
    }

    func test_ceiling_belowTheMinimumSpeed_stopsAtTheCeiling() {
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 115),
            velocity: -40,
            visualBounds: outline,
            in: area
        )

        XCTAssertFalse(bounce.didBounce)
        XCTAssertEqual(bounce.velocity, 0)
        XCTAssertEqual(bounce.position.y, 120)
    }

    /// Degenerate but reachable via the size slider: an avatar scaled wider
    /// than the display has no position that fits. It must still end up
    /// somewhere visible rather than at an inverted clamp.
    func test_contain_petWiderThanTheScreen_pinsToTheLeftEdge() {
        let huge = CGRect(x: -900, y: -200, width: 1800, height: 200)

        let contained = ScreenBounds.contain(CGPoint(x: 500, y: 0), visualBounds: huge, in: area)

        XCTAssertEqual(contained.x, 900, "its left edge sits on the screen's left edge")
    }
}

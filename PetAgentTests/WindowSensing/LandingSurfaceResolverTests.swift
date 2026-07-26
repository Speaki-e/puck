//
//  LandingSurfaceResolverTests.swift
//  PetAgent
//
//  F4 test · owner: 박해영 (Haeyoung Park)
//  Landing-surface resolution accounting for Z-order/overlap, per
//  plan/02_pet-app.md section 3 F4 ("Z순서·겹침 고려해 캐릭터 x좌표에서
//  실제 보이는 창 상단 엣지 세그먼트만 인정").
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class LandingSurfaceResolverTests: XCTestCase {
    private func window(_ frame: CGRect) -> WindowInfo {
        WindowInfo(windowID: 0, ownerPID: 0, ownerName: nil, title: nil, layer: 0, frame: frame)
    }

    func test_landsOnWindowTopEdge_whenWindowIsBelowCharacter() {
        let win = window(CGRect(x: 0, y: 300, width: 200, height: 100))

        let y = LandingSurfaceResolver.landingY(
            atX: 50, fallingFromY: 0, windows: [win], screenBottomY: 1080
        )

        XCTAssertEqual(y, 300)
    }

    func test_ignoresWindow_thatDoesNotSpanX() {
        let win = window(CGRect(x: 500, y: 300, width: 200, height: 100))

        let y = LandingSurfaceResolver.landingY(
            atX: 50, fallingFromY: 0, windows: [win], screenBottomY: 1080
        )

        XCTAssertEqual(y, 1080) // falls through to the screen bottom
    }

    func test_ignoresWindow_alreadyAboveCurrentPosition() {
        // Window's top edge (y=50) is above where the character currently is (y=200) —
        // it has already been passed while falling, so it shouldn't be a candidate.
        let win = window(CGRect(x: 0, y: 50, width: 200, height: 100))

        let y = LandingSurfaceResolver.landingY(
            atX: 50, fallingFromY: 200, windows: [win], screenBottomY: 1080
        )

        XCTAssertEqual(y, 1080)
    }

    func test_picksNearestSurface_whenMultipleWindowsBelow() {
        let nearer = window(CGRect(x: 0, y: 300, width: 200, height: 100))
        let farther = window(CGRect(x: 0, y: 600, width: 200, height: 100))

        let y = LandingSurfaceResolver.landingY(
            atX: 50, fallingFromY: 0, windows: [nearer, farther], screenBottomY: 1080
        )

        XCTAssertEqual(y, 300)
    }

    func test_occludedTopEdge_isNotACandidate() {
        // `back` sits behind `front` in Z-order (index 0 = frontmost). `front`'s frame
        // fully covers the point above `back`'s top edge, so `back`'s top edge is hidden.
        let front = window(CGRect(x: 0, y: 250, width: 200, height: 200)) // spans y 250...450
        let back = window(CGRect(x: 0, y: 300, width: 200, height: 100)) // top edge at y=300, inside front's span

        let y = LandingSurfaceResolver.landingY(
            atX: 50, fallingFromY: 0, windows: [front, back], screenBottomY: 1080
        )

        // back's top edge (300) is occluded by front, so the pet lands on front's own top edge (250)
        XCTAssertEqual(y, 250)
    }

    func test_unoccludedTopEdge_ofBackWindow_isStillACandidate() {
        // `front` is in front in Z-order but doesn't overlap `back`'s top-edge point,
        // so `back`'s top edge remains a valid, visible landing surface.
        let front = window(CGRect(x: 0, y: 500, width: 200, height: 100)) // spans y 500...600, doesn't cover y=300
        let back = window(CGRect(x: 0, y: 300, width: 200, height: 100))

        let y = LandingSurfaceResolver.landingY(
            atX: 50, fallingFromY: 0, windows: [front, back], screenBottomY: 1080
        )

        XCTAssertEqual(y, 300)
    }

    func test_noWindowsAtAll_fallsThroughToScreenBottom() {
        let y = LandingSurfaceResolver.landingY(atX: 50, fallingFromY: 0, windows: [], screenBottomY: 1080)

        XCTAssertEqual(y, 1080)
    }
}

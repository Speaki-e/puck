//
//  ScreenSpaceMapperTests.swift
//  Shaydi
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  World <-> screen pixel conversion, per plan/02_pet-app.md F1 ("모든 이동
//  로직은 픽셀 좌표만 다루고 렌더 직전에만 3D 변환") and protocol section 6's
//  scale convention (avatar height 1 unit = 100px on screen).
//

import XCTest
import CoreGraphics
import simd
@testable import Shaydi

final class ScreenSpaceMapperTests: XCTestCase {
    private let mapper = ScreenSpaceMapper(viewportSize: CGSize(width: 1920, height: 1080))

    func test_viewportCenter_mapsToWorldOrigin() {
        let world = mapper.worldPosition(forScreenPoint: CGPoint(x: 960, y: 540))
        XCTAssertEqual(world, SIMD3<Float>(0, 0, 0))
    }

    func test_pointRightOfCenter_mapsToPositiveWorldX() {
        let world = mapper.worldPosition(forScreenPoint: CGPoint(x: 1060, y: 540)) // 100px right of center
        XCTAssertEqual(world.x, 1, accuracy: 0.0001) // 100px = 1 unit
        XCTAssertEqual(world.y, 0, accuracy: 0.0001)
    }

    func test_pointAboveCenter_mapsToPositiveWorldY() {
        // Pixel Y decreases going up (Y-down screen space); world Y increases going up (Y-up).
        let world = mapper.worldPosition(forScreenPoint: CGPoint(x: 960, y: 440)) // 100px above center
        XCTAssertEqual(world.y, 1, accuracy: 0.0001)
    }

    func test_pointBelowCenter_mapsToNegativeWorldY() {
        let world = mapper.worldPosition(forScreenPoint: CGPoint(x: 960, y: 640)) // 100px below center
        XCTAssertEqual(world.y, -1, accuracy: 0.0001)
    }

    func test_worldPositionIsAlwaysOnZeroDepthPlane() {
        let world = mapper.worldPosition(forScreenPoint: CGPoint(x: 100, y: 100))
        XCTAssertEqual(world.z, 0)
    }

    func test_screenPoint_isInverseOfWorldPosition() {
        let original = CGPoint(x: 342, y: 781)
        let roundTripped = mapper.screenPoint(forWorldPosition: mapper.worldPosition(forScreenPoint: original))

        XCTAssertEqual(roundTripped.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(roundTripped.y, original.y, accuracy: 0.0001)
    }
}

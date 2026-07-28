//
//  SpriteLayerViewTests.swift
//  PetAgent
//
//  F1 test · owner: 박해영 (Haeyoung Park)
//  Smoke coverage for the 2026-07-29 2D switch's CALayer-backed replacement
//  for PetARView -- see SpriteLayerView's own doc comment for why this
//  doesn't need RealityKit's alpha-halo mitigation dance at all.
//

import XCTest
@testable import PetAgent

final class SpriteLayerViewTests: XCTestCase {
    func test_isFlipped_soTopLeftOriginMatchesGlobalScreenSpace() {
        let view = SpriteLayerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(view.isFlipped)
    }

    func test_initDoesNotCrash_andParentsContentLayerUnderTheViewsLayer() {
        let view = SpriteLayerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(view.wantsLayer)
        XCTAssertTrue(view.layer?.sublayers?.contains(view.contentLayer) ?? false)
    }
}

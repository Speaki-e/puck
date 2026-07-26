//
//  PetARViewTests.swift
//  PetAgent
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  Smoke coverage only — RealityKit rendering correctness (transparency,
//  alpha halo) can't be verified headlessly; see PetARView's own comments
//  for the mitigation procedure that needs a real running avatar to evaluate.
//

import XCTest
import RealityKit
@testable import PetAgent

final class PetARViewTests: XCTestCase {
    func test_initDoesNotCrash_andAddsACameraAnchor() {
        let view = PetARView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(view.scene.anchors.count, 1)
    }
}

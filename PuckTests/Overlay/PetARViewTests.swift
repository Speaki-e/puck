//
//  PetARViewTests.swift
//  Puck
//
//  F1 test · owner: 강상우 (Sangwoo Kang)
//  Smoke coverage only — RealityKit rendering correctness (transparency,
//  alpha halo) can't be verified headlessly; see PetARView's own comments
//  for the mitigation procedure that needs a real running avatar to evaluate.
//

import XCTest
import RealityKit
@testable import Puck

final class PetARViewTests: XCTestCase {
    func test_initDoesNotCrash_andAddsCameraAndContentAnchors() {
        let view = PetARView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        // One anchor for the fixed camera, one (separate, world-space) anchor
        // avatar entities attach to — see PetARView.contentAnchor's doc comment.
        XCTAssertEqual(view.scene.anchors.count, 2)
    }
}

//
//  ClickDetectorTests.swift
//  PetAgent
//
//  F10 test · owner: 박해영 (Haeyoung Park)
//  Pure hit test: plan/02_pet-app.md F10 ("클릭 감지: 전역 클릭 모니터로 클릭
//  좌표의 대상 frame 포함 여부 확인").
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class ClickDetectorTests: XCTestCase {
    private let targetFrame = CGRect(x: 100, y: 100, width: 50, height: 50)

    func test_clickInsideFrame_isDetected() {
        XCTAssertTrue(ClickDetector.isClick(at: CGPoint(x: 125, y: 125), insideTargetFrame: targetFrame))
    }

    func test_clickOutsideFrame_isNotDetected() {
        XCTAssertFalse(ClickDetector.isClick(at: CGPoint(x: 0, y: 0), insideTargetFrame: targetFrame))
    }
}

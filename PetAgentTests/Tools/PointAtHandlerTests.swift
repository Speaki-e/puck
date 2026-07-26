//
//  PointAtHandlerTests.swift
//  PetAgent
//
//  F11 test · owner: 박해영 (Haeyoung Park)
//  tool_result(ok) must fire at Point *start*, per protocol section 4
//  ("Point 시작 시점에 tool_result(ok) 반환") — verified against a real
//  PointingController wired to a fake ClickDetectorProviding (no real
//  global event monitor).
//

import XCTest
import CoreGraphics
@testable import PetAgent

private final class FakeClickDetector: ClickDetectorProviding {
    var onClickInsideTarget: (() -> Void)?
    func startMonitoring(targetFrame: CGRect) {}
    func stopMonitoring() {}
}

final class PointAtHandlerTests: XCTestCase {
    func test_validFrame_repliesOkAsSoonAsPointingStarts() {
        let handler = PointAtHandler(pointingController: PointingController(clickDetector: FakeClickDetector()))
        let args = JSONValue.object([
            "frame": .object([
                "x": .number(10), "y": .number(20), "width": .number(30), "height": .number(40),
            ]),
        ])

        let expectation = expectation(description: "completion called")
        handler.execute(args: args) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_missingFrame_failsWithExecutionFailed() {
        let handler = PointAtHandler(pointingController: PointingController(clickDetector: FakeClickDetector()))

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("point_at requires a frame {x,y,width,height}"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}

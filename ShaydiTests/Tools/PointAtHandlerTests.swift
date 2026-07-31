//
//  PointAtHandlerTests.swift
//  Shaydi
//
//  F10/F11 test · owner: 박해영 (Haeyoung Park)
//  protocol section 4: point_at means "펫이 좌표로 이동해 가리킴", and
//  tool_result(ok) comes back the moment Point *starts* — not when the
//  command is received, and not when pointing ends.
//

import XCTest
import CoreGraphics
@testable import Shaydi

private final class SpyPointingCoordinator: PetPointingCoordinating {
    private(set) var requestedFrames: [CGRect] = []
    private(set) var cancelCount = 0
    private var pending: (() -> Void)?

    func pointAt(frame: CGRect, onPointingStarted: @escaping () -> Void) {
        requestedFrames.append(frame)
        pending = onPointingStarted
    }

    func cancelPointing() {
        cancelCount += 1
    }

    /// Simulates the pet finishing its walk and entering Point.
    func completeArrival() {
        pending?()
        pending = nil
    }
}

final class PointAtHandlerTests: XCTestCase {
    private let frameArgs = JSONValue.object([
        "frame": .object([
            "x": .number(100), "y": .number(200), "width": .number(50), "height": .number(20),
        ]),
    ])

    func test_missingFrame_failsWithExecutionFailed() {
        let handler = PointAtHandler(coordinator: SpyPointingCoordinator())

        let done = expectation(description: "completion called")
        handler.execute(args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("point_at requires a frame {x,y,width,height}"))
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func test_sendsThePetToTheTargetFrame() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        handler.execute(args: frameArgs) { _ in }

        XCTAssertEqual(coordinator.requestedFrames, [CGRect(x: 100, y: 200, width: 50, height: 20)])
    }

    /// The old handler replied the instant it was called, before the pet had
    /// gone anywhere — the agent would tell the user it had been shown
    /// something it had not yet been shown.
    func test_doesNotReplyUntilPointingActuallyStarts() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        var replied = false
        handler.execute(args: frameArgs) { _ in replied = true }
        XCTAssertFalse(replied, "the pet is still walking there")

        coordinator.completeArrival()
        XCTAssertTrue(replied)
    }

    func test_repliesSuccessOncePointingStarts() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        var ok: Bool?
        handler.execute(args: frameArgs) { result in
            if case .success = result { ok = true } else { ok = false }
        }
        coordinator.completeArrival()

        XCTAssertEqual(ok, true)
    }

    /// ToolExecutor's default cancel() is a no-op -- a cancelled point_at
    /// left AppDelegate.pendingPointTracker's entry live, so the pet kept
    /// walking/pointing on the caller's behalf after cancellation (found via
    /// review).
    func test_cancel_tellsTheCoordinatorToCancelPointing() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        handler.cancel()

        XCTAssertEqual(coordinator.cancelCount, 1)
    }
}

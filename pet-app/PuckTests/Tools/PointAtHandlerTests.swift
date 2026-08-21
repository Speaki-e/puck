//
//  PointAtHandlerTests.swift
//  Puck
//
//  F10/F11 test · owner: 박해영 (Haeyoung Park)
//  protocol section 4: point_at means "펫이 좌표로 이동해 가리킴", and
//  tool_result(ok) comes back the moment Point *starts* — not when the
//  command is received, and not when pointing ends.
//

import XCTest
import CoreGraphics
@testable import Puck

private final class SpyPointingCoordinator: PetPointingCoordinating {
    private(set) var requestedFrames: [CGRect] = []
    private(set) var requestedHolds: [TimeInterval?] = []
    private(set) var cancelCount = 0
    private var pending: (() -> Void)?

    func pointAt(frame: CGRect, holdSeconds: TimeInterval?, onPointingStarted: @escaping () -> Void) {
        requestedFrames.append(frame)
        requestedHolds.append(holdSeconds)
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
        handler.execute(id: "test", args: .object([:])) { result in
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

        handler.execute(id: "test", args: frameArgs) { _ in }

        XCTAssertEqual(coordinator.requestedFrames, [CGRect(x: 100, y: 200, width: 50, height: 20)])
    }

    /// The old handler replied the instant it was called, before the pet had
    /// gone anywhere — the agent would tell the user it had been shown
    /// something it had not yet been shown.
    func test_doesNotReplyUntilPointingActuallyStarts() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        var replied = false
        handler.execute(id: "test", args: frameArgs) { _ in replied = true }
        XCTAssertFalse(replied, "the pet is still walking there")

        coordinator.completeArrival()
        XCTAssertTrue(replied)
    }

    func test_repliesSuccessOncePointingStarts() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        var ok: Bool?
        handler.execute(id: "test", args: frameArgs) { result in
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
        handler.execute(id: "test", args: frameArgs) { _ in }

        handler.cancel(id: "test")

        XCTAssertEqual(coordinator.cancelCount, 1)
    }

    /// One handler instance serves every point_at, and there is only one pet,
    /// so a second call supersedes the first. Its cancel must not then stop
    /// the pointing the second call is doing -- which is what a 30s timeout on
    /// the abandoned first call would otherwise do.
    func test_cancelOfASupersededCall_doesNotStopTheCurrentOne() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)
        handler.execute(id: "first", args: frameArgs) { _ in }
        handler.execute(id: "second", args: frameArgs) { _ in }

        handler.cancel(id: "first")

        XCTAssertEqual(coordinator.cancelCount, 0, "the current point_at must keep going")

        handler.cancel(id: "second")
        XCTAssertEqual(coordinator.cancelCount, 1)
    }

    /// ToolExecutor only cancels ids it dispatched, but a cancel racing a
    /// completion can arrive for one that has already finished.
    func test_cancelOfAnUnknownId_isANoOp() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        handler.cancel(id: "never-dispatched")

        XCTAssertEqual(coordinator.cancelCount, 0)
    }

    /// A tour stop holds until the next stop; a plain point_at keeps the 8s
    /// default so nothing that already calls it changes.
    func test_holdSeconds_isPassedThroughWhenGiven() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)
        let args = JSONValue.object([
            "frame": .object([
                "x": .number(100), "y": .number(200), "width": .number(50), "height": .number(20),
            ]),
            "hold_seconds": .number(45),
        ])

        handler.execute(id: "t", args: args) { _ in }

        XCTAssertEqual(coordinator.requestedHolds, [45])
    }

    func test_holdSeconds_omitted_leavesTheDefault() {
        let coordinator = SpyPointingCoordinator()
        let handler = PointAtHandler(coordinator: coordinator)

        handler.execute(id: "t", args: frameArgs) { _ in }

        XCTAssertEqual(coordinator.requestedHolds, [nil])
    }

    /// The cap exists so a run that never reports finishing cannot leave the
    /// pet pointing for the rest of the session.
    func test_holdSeconds_isCappedAndGarbageFallsBackToTheDefault() {
        XCTAssertEqual(
            PointAtHandler.holdSeconds(from: .object(["hold_seconds": .number(9999)])),
            PointAtHandler.maximumHoldSeconds
        )
        XCTAssertNil(PointAtHandler.holdSeconds(from: .object(["hold_seconds": .number(-1)])))
        XCTAssertNil(PointAtHandler.holdSeconds(from: .object(["hold_seconds": .number(.infinity)])))
    }
}

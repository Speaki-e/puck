//
//  PointAtHandler.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  Delegates a MoveTo+Point command to the F3 FSM (tool execution = pet action, a special case)
//
//  protocol section 4: point_at is "펫이 좌표로 이동해 가리킴" and returns
//  "Point 시작 시점에". The handler owns neither the walking nor the pointing
//  timer — it hands the target to whoever drives the FSM and replies once
//  that reports the pet has actually started pointing.
//

import CoreGraphics

/// How PointAtHandler asks the FSM to carry out a point_at. Implemented at
/// bootstrap, where the character controller and pointing timer both live.
protocol PetPointingCoordinating: AnyObject {
    /// Walks the pet to `frame` and starts pointing at it.
    /// - Parameter onPointingStarted: called when Point actually begins.
    func pointAt(frame: CGRect, onPointingStarted: @escaping () -> Void)

    /// Abandons the in-flight point_at (tool_cancel or ToolExecutor's
    /// timeout) -- without this the pet kept walking/pointing on the
    /// caller's behalf after cancellation (found via review).
    func cancelPointing()
}

final class PointAtHandler: ToolHandler {
    let toolName = "point_at"
    private let coordinator: PetPointingCoordinating

    init(coordinator: PetPointingCoordinating) {
        self.coordinator = coordinator
    }

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let frame = args.extractFrame() else {
            completion(.failure(.executionFailed("point_at requires a frame {x,y,width,height}")))
            return
        }

        coordinator.pointAt(frame: frame) {
            completion(.success(nil))
        }
    }

    func cancel() {
        coordinator.cancelPointing()
    }
}

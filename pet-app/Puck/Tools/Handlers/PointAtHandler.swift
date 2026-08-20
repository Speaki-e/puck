//
//  PointAtHandler.swift
//  Puck
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
import Foundation

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

    /// The dispatch the pet is currently walking/pointing for. There is one
    /// pet, so a second point_at replaces the first rather than running
    /// beside it -- but a *cancel* still has to name which call it is for, or
    /// the 30s timeout of a superseded call stops the pointing its replacement
    /// is doing. Guarded: `execute` runs on the caller's queue and `cancel`
    /// arrives from ToolExecutor's.
    private let stateQueue = DispatchQueue(label: "Puck.PointAtHandler.state")
    private var activeID: String?

    init(coordinator: PetPointingCoordinating) {
        self.coordinator = coordinator
    }

    func execute(id: String, args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let frame = args.extractFrame() else {
            completion(.failure(.executionFailed("point_at requires a frame {x,y,width,height}")))
            return
        }

        stateQueue.sync { activeID = id }
        coordinator.pointAt(frame: frame) { [weak self] in
            self?.stateQueue.sync { if self?.activeID == id { self?.activeID = nil } }
            completion(.success(nil))
        }
    }

    func cancel(id: String) {
        let isCurrent = stateQueue.sync {
            guard activeID == id else { return false }
            activeID = nil
            return true
        }
        guard isCurrent else { return }
        coordinator.cancelPointing()
    }
}

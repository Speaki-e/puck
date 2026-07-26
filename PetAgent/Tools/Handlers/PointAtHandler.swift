//
//  PointAtHandler.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  Delegates a MoveTo+Point command to the F3 FSM (tool execution = pet action, a special case)
//
//  TODO(F3): PointingController.beginPointing assumes the pet has already
//  arrived at the target — real MoveTo movement math isn't implemented yet
//  (Movement/States/MoveToState.swift), so this currently starts the Point
//  loop/click-or-8s-release timer immediately rather than actually walking
//  there first. Wire in real MoveTo-arrival once F3 lands it.

import CoreGraphics

/// args: `{"frame": {"x":_, "y":_, "width":_, "height":_}}` (protocol section 4).
extension JSONValue {
    func extractFrame(key: String = "frame") -> CGRect? {
        guard case .object(let fields) = self, case .object(let frameFields) = fields[key] else {
            return nil
        }
        guard
            case .number(let x)? = frameFields["x"],
            case .number(let y)? = frameFields["y"],
            case .number(let width)? = frameFields["width"],
            case .number(let height)? = frameFields["height"]
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

final class PointAtHandler: ToolHandler {
    let toolName = "point_at"
    private let pointingController: PointingController

    init(pointingController: PointingController) {
        self.pointingController = pointingController
    }

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let frame = args.extractFrame() else {
            completion(.failure(.executionFailed("point_at requires a frame {x,y,width,height}")))
            return
        }

        // tool_result(ok) fires here, at Point *start* — not when pointing ends.
        pointingController.onPointingStarted = {
            completion(.success(nil))
        }
        pointingController.beginPointing(targetFrame: frame)
    }
}

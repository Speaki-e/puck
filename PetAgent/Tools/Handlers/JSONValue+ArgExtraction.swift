//
//  JSONValue+ArgExtraction.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  Shared tool_dispatch argument extraction, used by multiple handlers.
//

import CoreGraphics

extension JSONValue {
    /// args: `{"frame": {"x":_, "y":_, "width":_, "height":_}}` (protocol section 4).
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

    /// args: `{"<key>": "..."}` — a single required top-level string field.
    func extractString(key: String) -> String? {
        guard case .object(let fields) = self, case .string(let value) = fields[key] else {
            return nil
        }
        return value
    }
}

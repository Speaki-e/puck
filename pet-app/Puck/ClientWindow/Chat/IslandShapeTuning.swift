//
//  IslandShapeTuning.swift
//  Puck
//
//  Temporary: the two numbers that decide the island's raised shoulder, live
//  and adjustable, so they can be settled by looking rather than by guessing.
//
//  Both default to the constants the shape shipped with, so a build nobody
//  has touched draws exactly what it drew before. Once the values are chosen
//  they belong back in IslandShape as constants and this file goes away --
//  see docs/tasks.md.
//

import SwiftUI

enum IslandShapeTuning {
    /// How far the shoulder rises above the rest of the top edge.
    static let riseKey = "Puck.islandShoulderRise"
    /// How much horizontal run the climb between the two levels takes.
    static let blendKey = "Puck.islandShoulderBlend"

    static let riseRange: ClosedRange<Double> = 0...80
    static let blendRange: ClosedRange<Double> = 8...200

    static var rise: CGFloat {
        stored(riseKey, default: Double(PetTankView.shoulderRise), in: riseRange)
    }

    static var blend: CGFloat {
        stored(blendKey, default: Double(IslandShape.blend), in: blendRange)
    }

    /// Read through the same clamp the rest of the stored sizes use: these
    /// are temporary knobs, and a temporary knob that can wedge the window is
    /// worse than no knob.
    private static func stored(_ key: String, default fallback: Double, in range: ClosedRange<Double>) -> CGFloat {
        let raw = UserDefaults.standard.object(forKey: key) as? Double ?? fallback
        guard raw.isFinite else { return CGFloat(fallback) }
        return CGFloat(min(max(raw, range.lowerBound), range.upperBound))
    }
}

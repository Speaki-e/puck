//
//  ScreenSpaceMapper.swift
//  Shaydi
//
//  F1 · owner: Sangwoo Kang
//  Single encapsulation of world <-> screen pixel coordinate conversion
//
//  All movement logic (F3) works purely in screen pixels; this is the only
//  place a pixel position gets converted to/from RealityKit world space, at
//  render time. PetARView's camera is placed far away with a narrow FOV
//  specifically so perspective distortion is negligible and this mapping can
//  stay a simple linear scale instead of a full projection — see
//  plan/02_pet-app.md F1 ("카메라를 멀리 + 좁은 FOV로 원근왜곡 최소화").

import CoreGraphics
import simd

struct ScreenSpaceMapper: Equatable {
    /// protocol section 6's scale convention: avatar height 1 world unit = 100 screen px.
    static let pixelsPerWorldUnit: CGFloat = 100

    /// This display's overlay window size, in pixels.
    let viewportSize: CGSize

    /// Screen-local pixel position (top-left origin, Y increases downward) ->
    /// world position on the z=0 depth plane the fixed camera is aimed at.
    func worldPosition(forScreenPoint point: CGPoint) -> SIMD3<Float> {
        let x = (point.x - viewportSize.width / 2) / Self.pixelsPerWorldUnit
        // Pixel Y increases downward; world Y increases upward — flip here, once.
        let y = (viewportSize.height / 2 - point.y) / Self.pixelsPerWorldUnit
        return SIMD3<Float>(Float(x), Float(y), 0)
    }

    /// Inverse of `worldPosition(forScreenPoint:)`.
    func screenPoint(forWorldPosition position: SIMD3<Float>) -> CGPoint {
        let x = CGFloat(position.x) * Self.pixelsPerWorldUnit + viewportSize.width / 2
        let y = viewportSize.height / 2 - CGFloat(position.y) * Self.pixelsPerWorldUnit
        return CGPoint(x: x, y: y)
    }
}

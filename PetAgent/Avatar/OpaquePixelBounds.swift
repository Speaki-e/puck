//
//  OpaquePixelBounds.swift
//  PetAgent
//
//  F2 · owner: 강상우 (Sangwoo Kang)
//  Finds the tight bounding box of an image's non-transparent pixels.
//
//  Avatar PNGs are authored with the character floating in a transparent
//  canvas, and how much padding surrounds it is entirely up to whoever drew
//  it. Treating the whole canvas as the character makes the pet stop short of
//  a screen edge by however much empty space its artist happened to leave.
//
//  Measured once per image at load time (a few ms for a 1200px sprite) and
//  cached by the caller -- never per frame.
//

import CoreGraphics
import Foundation

enum OpaquePixelBounds {
    /// Pixels at or below this alpha count as transparent. Not zero: PNG
    /// anti-aliasing leaves a fringe of nearly-invisible pixels around the
    /// artwork, and including them puts the "edge" a few pixels outside
    /// anything a person can actually see.
    static let alphaThreshold: UInt8 = 10

    /// The bounding box of `image`'s visible pixels, in image pixel
    /// coordinates with a top-left origin. Nil if the image is fully
    /// transparent -- callers fall back to the full canvas rather than to an
    /// empty rect, since a pet with a zero-width outline can never be inside
    /// the screen at all.
    static func of(_ image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // Redrawn into a known 8-bit alpha-last layout: CGImage can be any of
        // a dozen pixel formats, and reading its raw data would mean handling
        // all of them.
        var alpha = [UInt8](repeating: 0, count: width * height)
        let ok = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // CGContext draws bottom-up; flip back to the top-left origin every
        // other coordinate in this app uses.
        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(height - 1 - maxY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }
}

//
//  TankArtwork.swift
//  Puck
//
//  The picture the pet's island is filled with.
//
//  This was a set of moods to choose between, picked from a menu on the
//  strip: seven gradients behind the island, none of them on it. There is one
//  picture now and no menu -- what the island is made of is part of what the
//  app looks like, not a preference, and a picker offering six gradients
//  beside it was six ways to make it worse.
//
//  Replaces TankBackground; the setting it was stored under is left behind
//  rather than migrated, since nothing reads it any more.
//

import AppKit

enum TankArtwork {
    /// The file, in the bundle's TankBackgrounds folder.
    static let name = "seabed"

    /// Loaded once and kept: this is asked for on every frame the island
    /// draws, and decoding a wide PNG per frame is not a thing to do.
    static func image() -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "TankBackgrounds"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// How wide one copy is per point of height. Guarded against a
    /// zero-height image, which would make the island's layout divide by it.
    static func aspect(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    private static let cache = NSCache<NSString, NSImage>()
}

//
//  TankBackground.swift
//  Puck
//
//  The backdrop the pet's island is drawn on, and the themes to pick from.
//  See docs/superpowers/specs/2026-08-22-tank-background-design.md.
//
//  The last three take their mood from a few well-worn fantasy motifs -- a
//  world tree holding reality up, a seam between dimensions, a quiet field
//  you cross over to. Drawn here as our own gradients: what is borrowed is
//  the atmosphere, not anyone's artwork or words.
//
//  Gradients only, and vertical ones at that. The tank is not one view but two
//  siblings -- the strip above the chat column and the strip above the editor
//  column -- and SwiftUI cannot draw across that split. Both segments are the
//  same height, so a top-to-bottom gradient comes out pixel-identical in each
//  and the boundary disappears. Anything that varies horizontally would be a
//  picture cut in half at the divider.
//

import AppKit
import SwiftUI

enum TankBackground: String, CaseIterable {
    case plain, night, forest, ocean
    case worldTree, boundary, meadow
    /// The one drawn picture in the set: a seabed the island is filled with
    /// rather than floated over. See `islandArtworkName`.
    case seabed

    /// Same shape as `ClientWindowStore.tankPinnedKey`. The value is read
    /// straight from UserDefaults by `PetTankView` rather than going through
    /// the store, because unlike pinning it is never sent to pet-app: the pet
    /// is drawn by the overlay window *above* this view and does not care what
    /// is behind it.
    static let storageKey = "Puck.tankBackground"

    var name: String {
        switch self {
        case .plain: return Strings.text(.tankBackgroundPlain)
        case .night: return Strings.text(.tankBackgroundNight)
        case .forest: return Strings.text(.tankBackgroundForest)
        case .ocean: return Strings.text(.tankBackgroundOcean)
        case .worldTree: return Strings.text(.tankBackgroundWorldTree)
        case .boundary: return Strings.text(.tankBackgroundBoundary)
        case .meadow: return Strings.text(.tankBackgroundMeadow)
        case .seabed: return Strings.text(.tankBackgroundSeabed)
        }
    }

    /// The artwork this background fills the island with, or nil for the ones
    /// that are a mood behind it.
    ///
    /// A picture *on* the island rather than behind it is a deliberate
    /// exception to the rule stated below -- asked for, and the reason the
    /// glass goes over it: what the pet stands on has to read as a surface,
    /// and a photograph under its feet does not. Frosted, it reads as looking
    /// down into water, which is what a tank is.
    var islandArtworkName: String? {
        switch self {
        case .seabed: return "seabed"
        default: return nil
        }
    }

    /// Loaded once and kept: this is asked for on every frame the island
    /// draws, and decoding a 1600pt PNG per frame is not a thing to do.
    static func artwork(named name: String) -> NSImage? {
        if let cached = artworkCache.object(forKey: name as NSString) { return cached }
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "TankBackgrounds"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        artworkCache.setObject(image, forKey: name as NSString)
        return image
    }

    private static let artworkCache = NSCache<NSString, NSImage>()

    /// Painted behind the island, never on it -- the island is the ground the
    /// pet stands on, and a pet standing on a picture reads as standing in
    /// it.
    ///
    /// `plain` paints nothing at all rather than the palette's ground: the
    /// window is translucent now, and an opaque rectangle around the island
    /// left a black band across the top of an otherwise see-through window.
    /// Nothing is what "no backdrop" should have meant all along.
    ///
    /// The named ones stay opaque and fixed. A mood is the whole point of
    /// choosing one, and one you can see the desktop through is not a mood.
    @ViewBuilder
    func backdrop(palette: ClientPalette) -> some View {
        switch self {
        case .plain:
            Color.clear
        case .night:
            Self.gradient(top: Color(red: 0.055, green: 0.075, blue: 0.169),
                          bottom: Color(red: 0.169, green: 0.208, blue: 0.373))
        // Light from above, dark below -- you are inside these two, and the
        // floor of a wood or a tank is the far end of the light, not the near
        // one. `night` runs the other way on purpose: a sky is darkest
        // overhead and brightest at the horizon.
        case .forest:
            Self.gradient(top: Color(red: 0.196, green: 0.376, blue: 0.243),
                          bottom: Color(red: 0.090, green: 0.200, blue: 0.141))
        case .ocean:
            Self.gradient(top: Color(red: 0.157, green: 0.494, blue: 0.647),
                          bottom: Color(red: 0.055, green: 0.243, blue: 0.376))
        // Light coming down through leaves onto roots: warm at the canopy,
        // deep green where it lands.
        case .worldTree:
            Self.gradient(top: Color(red: 0.847, green: 0.702, blue: 0.353),
                          bottom: Color(red: 0.106, green: 0.235, blue: 0.180))
        // A seam, so the two ends disagree: violet above, a colder blue
        // below, with the join left visible rather than blended away.
        case .boundary:
            Self.gradient(top: Color(red: 0.396, green: 0.239, blue: 0.639),
                          bottom: Color(red: 0.145, green: 0.184, blue: 0.416))
        // Late afternoon over open ground -- the gentlest of the set, since
        // the idea it comes from is somewhere you arrive rather than end.
        case .meadow:
            Self.gradient(top: Color(red: 0.945, green: 0.804, blue: 0.616),
                          bottom: Color(red: 0.443, green: 0.545, blue: 0.373))
        // Nothing, like `plain`. The picture is the island's own fill, and a
        // matching blue behind it filled the strip edge to edge in the same
        // colours -- so the island lost its outline and the whole band read
        // as one sheet of water running under the toolbar and off the side of
        // the window. What makes it an island is the ground showing around it.
        case .seabed:
            Color.clear
        }
    }

    private static func gradient(top: Color, bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

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

import SwiftUI

enum TankBackground: String, CaseIterable {
    case plain, night, forest, ocean
    case worldTree, boundary, meadow

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
        }
    }

    /// `plain` follows the app palette; the other three are fixed. A mood is
    /// the whole point of picking one -- lightening "night" in light mode
    /// would stop it being night.
    @ViewBuilder
    func backdrop(palette: ClientPalette) -> some View {
        switch self {
        case .plain:
            palette.surface
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
        }
    }

    private static func gradient(top: Color, bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

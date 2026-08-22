//
//  TankBackground.swift
//  Puck
//
//  The backdrop the pet's tank is drawn on, and the four themes to pick from.
//  See docs/superpowers/specs/2026-08-22-tank-background-design.md.
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
        }
    }

    private static func gradient(top: Color, bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

//
//  ClientPalette.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- see
//  docs/superpowers/specs/2026-08-14-design-system-v2-design.md. Two
//  independently art-directed palettes (light/dark), not a light/dark axis
//  crossed with a flat/glass axis -- `.glass` is gone (macOS 26+-only
//  upkeep cost wasn't worth it for a mood nobody asked to keep).
//

import SwiftUI

struct ClientPalette {
    var background: Color
    var surface: Color
    var surfaceBorder: Color
    var textPrimary: Color
    var textSecondary: Color
    /// The one deliberately loud color -- send button, active row, one
    /// empty-state glow. Not used anywhere else. Identical in every
    /// palette and in chat-web/workspace's --brand.
    var accent: Color
    /// Text/icons drawn directly on a solid `accent` fill.
    var onAccent: Color
    /// Status-color vocabulary (v2, new) -- session/run/connection state,
    /// git-style diff coloring. `statusIdle`/`statusActive` are computed
    /// rather than stored so they can never drift from `textSecondary`/
    /// `accent`.
    var statusSuccess: Color
    var statusError: Color
    var statusWarning: Color

    var statusIdle: Color { textSecondary }
    var statusActive: Color { accent }

    static let light = ClientPalette(
        background: Color(red: 0.980, green: 0.980, blue: 0.980), // #fafafa
        surface: .white, // #ffffff
        surfaceBorder: Color(red: 0.898, green: 0.898, blue: 0.898), // #e5e5e5
        textPrimary: Color(red: 0.102, green: 0.102, blue: 0.102), // #1a1a1a
        textSecondary: Color(red: 0.420, green: 0.420, blue: 0.420), // #6b6b6b
        accent: Color(red: 0.929, green: 0.549, blue: 0.200), // #ed8c33
        onAccent: .white,
        statusSuccess: Color(red: 0.247, green: 0.725, blue: 0.314), // #3fb950
        statusError: Color(red: 0.973, green: 0.318, blue: 0.286), // #f85149
        statusWarning: Color(red: 0.890, green: 0.702, blue: 0.255) // #e3b341
    )

    static let dark = ClientPalette(
        background: Color(red: 0.039, green: 0.039, blue: 0.039), // #0a0a0a
        surface: Color(red: 0.075, green: 0.075, blue: 0.075), // #131313
        surfaceBorder: Color(red: 0.141, green: 0.141, blue: 0.141), // #242424
        textPrimary: Color(red: 0.929, green: 0.929, blue: 0.929), // #ededed
        textSecondary: Color(red: 0.478, green: 0.478, blue: 0.478), // #7a7a7a
        accent: Color(red: 0.929, green: 0.549, blue: 0.200), // #ed8c33
        onAccent: Color(red: 0.086, green: 0.086, blue: 0.086), // #161616 -- near-black reads better on accent than white here
        statusSuccess: Color(red: 0.247, green: 0.725, blue: 0.314), // #3fb950
        statusError: Color(red: 0.973, green: 0.318, blue: 0.286), // #f85149
        statusWarning: Color(red: 0.890, green: 0.702, blue: 0.255) // #e3b341
    )
}

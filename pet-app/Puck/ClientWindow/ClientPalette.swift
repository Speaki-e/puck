//
//  ClientPalette.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The color half of a ClientThemeStyle. Three complete, independently
//  art-directed token sets rather than one palette with per-mode color
//  swaps -- byeolki wanted "다크, 화이트, 글래스" as three distinct moods,
//  not a light/dark axis crossed with a flat/glass axis.
//

import SwiftUI

struct ClientPalette {
    var background: Color
    var surface: Color
    var surfaceBorder: Color
    var textPrimary: Color
    var textSecondary: Color
    /// The one deliberately loud color -- send button, user's own bubble,
    /// active sidebar row, one empty-state glow. Not used anywhere else.
    var accent: Color
    /// Text/icons drawn directly on a solid `accent` fill.
    var onAccent: Color
    var success: Color
    var failure: Color
    var warning: Color
    /// true only for `.glass` -- components render through
    /// `themedSurface(_:in:)` (see GlassSurface.swift), which branches to
    /// real `glassEffect` here and a flat bordered fill everywhere else.
    var usesGlassSurfaces: Bool

    // workspace (the Electron/web client window) is the design source of
    // truth: `.dark` below matches its tokens (src/renderer/styles.css's
    // --canvas/--surface/--hairline/--ink/--mute/--blue) pixel-for-pixel.
    // `.light`/`.glass` are untouched since workspace has no light mode.
    static let light = ClientPalette(
        background: .white, // Gray/White Alpha 0 #FFFFFF
        surface: .white,
        surfaceBorder: Color(red: 0.933, green: 0.914, blue: 0.941), // Gray/+5 #EEE9F0
        textPrimary: Color(red: 0.200, green: 0.169, blue: 0.212), // Gray/-3 #332B36
        textSecondary: Color(red: 0.412, green: 0.369, blue: 0.431), // Gray/0 #695E6E
        accent: Color(red: 0.80, green: 0.42, blue: 0.12),
        onAccent: .white,
        success: .green,
        failure: .red,
        warning: .orange,
        usesGlassSurfaces: false
    )

    static let dark = ClientPalette(
        background: Color(red: 0.035, green: 0.035, blue: 0.035), // workspace --canvas #090909
        surface: Color(red: 0.067, green: 0.067, blue: 0.067), // workspace --surface #111111
        surfaceBorder: Color(red: 0.161, green: 0.161, blue: 0.161), // workspace --hairline #292929
        textPrimary: Color(red: 0.929, green: 0.929, blue: 0.929), // workspace --ink #ededed
        textSecondary: Color(red: 0.467, green: 0.467, blue: 0.467), // workspace --mute #777777
        accent: Color(red: 0.196, green: 0.569, blue: 1.0), // workspace --blue #3291ff
        onAccent: .white,
        success: .green,
        failure: .red,
        warning: .orange,
        usesGlassSurfaces: false
    )

    /// Fixed dark backdrop -- translucency reads best over a dark surface
    /// (see ClientThemeStyle.colorScheme's own reasoning). `surface`/
    /// `surfaceBorder` here are only the pre-macOS-26 `.regularMaterial`
    /// fallback's tint; on macOS 26+, `themedSurface` ignores them and uses
    /// real `glassEffect` instead.
    static let glass = ClientPalette(
        background: Color(red: 0.086, green: 0.086, blue: 0.086),
        surface: Color.white.opacity(0.06),
        surfaceBorder: Color.white.opacity(0.12),
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.6),
        accent: Color(red: 0.93, green: 0.55, blue: 0.20),
        onAccent: .white,
        success: .green,
        failure: .red,
        warning: .orange,
        usesGlassSurfaces: true
    )
}

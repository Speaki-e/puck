//
//  ClientPalette.swift
//  Shaydi
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

    // 2026-08-02: neutral tokens (background/border/text) pulled to match
    // the "Gray" scale of byeolki's 5 Figma references pixel-for-pixel
    // ("ㅇㄴㅇㄴ 그냥 똑같이 해달라고" -- after an earlier pass that only
    // touched two components, byeolki wants the visual style matched, not
    // just cherry-picked). `accent` stays the established pumpkin orange,
    // not Figma's neutral/black send button -- that's this app's own brand
    // color (byeolki, 2026-07-30: "호박을 로고로 쓰고 싶어"), deliberately
    // out of scope for a "match Figma's colors" pass.
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
        background: Color(red: 0.086, green: 0.086, blue: 0.086), // #161616
        surface: Color(red: 0.122, green: 0.122, blue: 0.122), // #1F1F1F
        surfaceBorder: Color(red: 0.165, green: 0.165, blue: 0.165), // #2A2A2A
        textPrimary: Color(red: 0.949, green: 0.949, blue: 0.941),
        textSecondary: Color(red: 0.549, green: 0.549, blue: 0.549),
        accent: Color(red: 0.93, green: 0.55, blue: 0.20),
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

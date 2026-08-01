//
//  GlassSurface.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Liquid Glass for the client window -- byeolki (2026-07-30): "client app의
//  ui를 애플 스타일로 리퀴드 글라스 사용해서".
//
//  `glassEffect` is macOS 26+ and the deployment target is still 14.0, so
//  every glass surface goes through here and falls back to the vibrant
//  material that was there before. One place to gate it instead of an
//  `#available` at every call site.
//

import SwiftUI

/// Groups glass siblings so the system blends them as one piece of material
/// (that grouping *is* Liquid Glass -- separately applied effects read as
/// unrelated blurred rectangles). No-op before macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = ClientTheme.Metrics.spacingMedium
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// A raised, translucent surface: chat bubbles, cards, the input bar.
    @ViewBuilder
    func glassSurface(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Same surface for something the pointer acts on (rows, buttons) --
    /// Liquid Glass reacts to hover/press on its own, which is most of what
    /// used to be signalled with an accent-tinted background.
    @ViewBuilder
    func glassControl(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.thickMaterial, in: shape)
        }
    }

    /// Glass only when `isEnabled` -- for rows and bubbles that are plain
    /// content until selected/owned, where the alternative is an `if` around
    /// a modifier chain at every call site (there were three private copies
    /// of this before).
    @ViewBuilder
    func glassSurface(in shape: some Shape, isEnabled: Bool) -> some View {
        if isEnabled {
            glassSurface(in: shape)
        } else {
            self
        }
    }

    /// The handful of surfaces the 2026-08-01 redesign deliberately colors
    /// (the send button, the "새 채팅" pill, the user's own bubble): a flat
    /// solid fill on every OS version, not `Glass.tint(_:)` on macOS 26+.
    ///
    /// 2026-08-01 (the Orbita-structured redesign): measured on the actual
    /// machine running macOS 26.5.1 -- `glassEffect(.regular.tint(accent),
    /// in:)` renders as visually indistinguishable from untinted glass (pixel
    /// -sampled a "tinted" button and a plain one: both landed on the same
    /// neutral gray, zero saturation). Real Liquid Glass tinting is
    /// apparently too subtle to read as color at all against this app's
    /// materials. `accent` only exists to be the one loud, unmistakable
    /// anchor every reference (Sense, the dark chat, Orbita) uses it for --
    /// an invisible "accent" defeats the entire point, so these two
    /// deliberately opt out of Liquid Glass and just paint the color, on
    /// every OS version alike (which also means the pre-26 fallback here no
    /// longer needs to be a special case).
    func glassSurface(in shape: some Shape, tint: Color) -> some View {
        background(tint, in: shape)
    }

    func glassControl(in shape: some Shape, tint: Color) -> some View {
        background(tint, in: shape)
    }
}

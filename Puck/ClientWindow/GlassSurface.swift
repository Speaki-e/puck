//
//  GlassSurface.swift
//  Puck
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
}

extension View {
    /// Flat, bordered surface for `.light`/`.dark` -- the non-glass
    /// counterpart to `glassSurface`.
    func borderedSurface(_ palette: ClientPalette, in shape: some Shape) -> some View {
        background(palette.surface, in: shape)
            .overlay(shape.stroke(palette.surfaceBorder, lineWidth: 1))
    }

    /// Picks glass vs. flat per the active theme -- every themed card/row/
    /// bubble in ChatView and the sidebar goes through this one call
    /// instead of choosing `glassSurface`/`borderedSurface` directly, same
    /// "one place to gate it" principle this file's header already states
    /// for the macOS-26-vs-fallback split.
    @ViewBuilder
    func themedSurface(_ palette: ClientPalette, in shape: some Shape) -> some View {
        if palette.usesGlassSurfaces {
            glassSurface(in: shape)
        } else {
            borderedSurface(palette, in: shape)
        }
    }
}

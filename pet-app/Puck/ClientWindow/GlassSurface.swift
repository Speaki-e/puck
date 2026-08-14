//
//  GlassSurface.swift
//  Puck
//
//  Design system v2 (2026-08-14): the `.glass` theme is gone, so this file
//  is down to the one surface style every theme actually uses. Kept as its
//  own file (rather than inlined at call sites) so the corner-style
//  pairing (fill + 1px border, same shape) stays declared in exactly one
//  place.
//

import SwiftUI

extension View {
    /// The flat, bordered surface every card/row/panel in the client
    /// window and Settings uses.
    func themedSurface(_ palette: ClientPalette, in shape: some Shape) -> some View {
        background(palette.surface, in: shape)
            .overlay(shape.stroke(palette.surfaceBorder, lineWidth: 1))
    }
}

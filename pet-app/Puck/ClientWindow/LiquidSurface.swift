//
//  LiquidSurface.swift
//  Puck
//
//  The glass every floating panel in the client window is cut from.
//
//  It started on the pet's island alone, which is what made it look wrong:
//  one panel lit from above with a specular edge, sitting beside a flat
//  sidebar and a flat file list, read as a thing from another window rather
//  than the same window's furniture. Spelled once here so the panels agree
//  about where the light is coming from.
//
//  Light is above and slightly to the left, for all of them. That is the
//  whole rule -- the sheen brightens the top, the specular sits just under
//  the top-left edge, and the border is brightest where it faces the light.
//

import SwiftUI

struct LiquidSurface: ViewModifier {
    let palette: ClientPalette
    var cornerRadius: CGFloat = ClientTheme.Metrics.panelCornerRadius
    /// How far the specular reaches, in points. Tied to the panel's own size
    /// rather than fixed: the same radius that reads as a highlight on the
    /// island covers a tall sidebar end to end.
    var specularRadius: CGFloat = 220
    /// Floating panels cast one; a surface that sits *in* the window (the
    /// composer) does not, or every control gains a drop shadow.
    var casts: Bool = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    palette.background
                    // Lit from above and pooling toward the bottom: the sheen
                    // is what makes it read as a surface with depth rather
                    // than a flat block.
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0),
                            .init(color: .white.opacity(0.04), location: 0.18),
                            .init(color: .white.opacity(0.01), location: 0.55),
                            .init(color: .black.opacity(0.16), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // The bright patch a curved glass surface throws. Off
                    // centre, or it reads as a second gradient rather than a
                    // highlight.
                    RadialGradient(
                        colors: [.white.opacity(0.07), .clear],
                        center: UnitPoint(x: 0.28, y: -0.2),
                        startRadius: 0,
                        endRadius: specularRadius
                    )
                    .blendMode(.plusLighter)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                // Brightest along the top edge and fading round the sides:
                // one light source, above. A border of even weight reads as a
                // drawn outline rather than a lit edge.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.26), location: 0),
                                .init(color: .white.opacity(0.08), location: 0.35),
                                .init(color: palette.surfaceBorder.opacity(0.55), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(casts ? 0.35 : 0), radius: casts ? 12 : 0, y: casts ? 5 : 0)
    }
}

extension View {
    /// Cuts this view out of the window's glass. `specularRadius` should be
    /// roughly the panel's long side, so a tall panel is not lit end to end.
    func liquidSurface(
        palette: ClientPalette,
        cornerRadius: CGFloat = ClientTheme.Metrics.panelCornerRadius,
        specularRadius: CGFloat = 220,
        casts: Bool = true
    ) -> some View {
        modifier(
            LiquidSurface(
                palette: palette,
                cornerRadius: cornerRadius,
                specularRadius: specularRadius,
                casts: casts
            )
        )
    }
}

extension View {
    /// A full-height column as a floating panel: the glass, inset from the
    /// window's edges so the backdrop shows around it.
    ///
    /// The inset is on the *outside* of the glass, so a column that already
    /// pads its own contents does not gain a second margin.
    func liquidSurfacePanel(palette: ClientPalette, specularRadius: CGFloat = 420) -> some View {
        liquidSurface(palette: palette, specularRadius: specularRadius)
            .padding(ClientTheme.Metrics.panelInset)
    }
}

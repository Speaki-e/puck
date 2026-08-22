//
//  PetTankView.swift
//  Puck
//
//  The pet's tank: a strip across the top of the chat (and the editor, when
//  it is open). Draws the glass, never the pet -- the pet is rendered by
//  Puck.app's overlay window on top of this, which is what keeps there being
//  exactly one pet. See the 2026-08-22 spec.
//

import SwiftUI

struct PetTankView: View {
    /// The strip's frame in AppKit global coordinates, or nil when it is off
    /// screen. Reported to the store, which forwards it over the socket.
    let onFrameChange: (CGRect?) -> Void

    @Environment(\.clientPalette) private var palette

    /// Tall enough for a 0.6-scale pet (about 72pt) with headroom to jump.
    static let height: CGFloat = 90

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.surface
            Rectangle()
                .fill(palette.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .frame(height: Self.height)
        .background(PaneFrameReporter(onChange: onFrameChange))
        .accessibilityHidden(true)
    }
}

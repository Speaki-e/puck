//
//  PetTankView.swift
//  Puck
//
//  The pet's island: a capsule floating across the top of the chat (and the
//  editor, when it is open). Draws the ground, never the pet -- the pet is
//  rendered by Puck.app's overlay window on top of this, which is what keeps
//  there being exactly one pet. See the 2026-08-22 spec.
//
//  A capsule rather than the full-bleed strip it started as: a strip reads as
//  part of the window's chrome, and the pet standing on it reads as standing
//  on a toolbar. Inset and rounded, it reads as a thing the pet is on rather
//  than an edge of the app -- the sidebar laid on its side.
//
//  The backdrop is themed (right-click to pick); see TankBackground.swift.
//

import SwiftUI

struct PetTankView: View {
    /// The strip's frame in AppKit global coordinates, or nil when it is off
    /// screen. Reported to the store, which forwards it over the socket.
    let onFrameChange: (CGRect?) -> Void

    @Environment(\.clientPalette) private var palette

    /// Read straight from UserDefaults rather than through ClientWindowStore:
    /// nothing about the choice leaves this app (see TankBackground). It also
    /// keeps the two segments in step for free -- both read the same key, so
    /// changing it in one redraws the other.
    @AppStorage(TankBackground.storageKey) private var storedBackground = TankBackground.plain.rawValue

    /// Tall enough for a 0.6-scale pet (about 72pt) with headroom to jump.
    static let height: CGFloat = 90

    /// How far the island floats from the window's own edges. The pet's world
    /// is the capsule, not this padding, which is why the frame is reported
    /// from inside it.
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 8

    /// The capsule itself.
    private var island: some View {
        ZStack(alignment: .bottom) {
            background.backdrop(palette: palette)
            // The floor the pet stands on, kept in every theme. Inset from
            // the rounded ends, where a full-width line would cut the corners.
            Rectangle()
                .fill(palette.textSecondary.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, Self.height / 2)
        }
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .strokeBorder(palette.surfaceBorder, lineWidth: 1)
        }
        // Floating, so it needs to sit above its own surroundings rather
        // than beside them.
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .background(PaneFrameReporter(onChange: onFrameChange))
    }

    /// An unknown value means a key written by a future version, or a hand-
    /// edited default -- falling back beats refusing to draw the tank.
    private var background: TankBackground {
        TankBackground(rawValue: storedBackground) ?? .plain
    }

    var body: some View {
        island
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, Self.verticalInset)
            .frame(height: Self.height)
        // Was `.accessibilityHidden(true)` while this was pure decoration. It
        // now carries the background menu, and a hidden element cannot be
        // reached to open one -- so the strip is collapsed into a single
        // labelled element instead, which keeps the decoration inside it
        // unannounced without making the menu unreachable.
        .accessibilityElement()
        .accessibilityLabel(Strings.text(.tankBackgroundMenu))
        .contextMenu {
            // Inline picker rather than a row of buttons: it renders the
            // checkmark for the current choice itself, and a plain (non-inline)
            // Picker would bury four flat options behind a submenu.
            Picker(Strings.text(.tankBackgroundMenu), selection: $storedBackground) {
                ForEach(TankBackground.allCases, id: \.self) { option in
                    Text(option.name).tag(option.rawValue)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

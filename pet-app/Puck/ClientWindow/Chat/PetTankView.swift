//
//  PetTankView.swift
//  Puck
//
//  The pet's island: a capsule floating across the top of the chat (and the
//  editor, when it is open). Draws the ground, never the pet -- the pet is
//  rendered by Puck.app's overlay window on top of this, which is what keeps
//  there being exactly one pet. See the 2026-08-22 spec.
//
//  A floating panel rather than the full-bleed strip it started as: a strip
//  reads as part of the window's chrome, and the pet standing on it reads as
//  standing on a toolbar. Inset, lightly rounded and lit from above, it reads
//  as a thing the pet is on -- the sidebar laid on its side.
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

    /// The island itself, and the pet's whole world while it is home. Tall
    /// enough for a 0.6-scale pet -- 133pt of avatar comes to 80 -- with
    /// headroom over it.
    ///
    /// Insetting *this* is what broke the move: the reported area is refused
    /// when it is shorter than the pet, so trimming 8pt off each end left 74
    /// against an 80pt pet and the pet simply stayed on the desktop. The
    /// padding goes outside instead.
    static let islandHeight: CGFloat = 90

    /// How far the island floats from the window's own edges.
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 8

    /// The strip the island floats in.
    static let height: CGFloat = islandHeight + verticalInset * 2

    /// Rounded, not a capsule. A pill turns the ends into arcs the pet cannot
    /// stand on and reads as a control; this is a panel with its corners
    /// taken off.
    static let cornerRadius: CGFloat = 14

    /// The island itself.
    private var island: some View {
        ZStack(alignment: .bottom) {
            background.backdrop(palette: palette)
            // Lit from above and pooling toward the bottom: the sheen is what
            // makes it read as a surface with depth rather than a flat block.
            LinearGradient(
                colors: [.white.opacity(0.10), .white.opacity(0.02), .black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            // The floor the pet stands on, kept in every theme.
            Rectangle()
                .fill(palette.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), palette.surfaceBorder.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        // Floating, so it needs to sit above its own surroundings rather
        // than beside them.
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        .frame(height: Self.islandHeight)
        // Reported from the island, not the padding around it: the pet's
        // world is the panel, and a frame taken from the padded box would
        // let it stand in the gap on either side.
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

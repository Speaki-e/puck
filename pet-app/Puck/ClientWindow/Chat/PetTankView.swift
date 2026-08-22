//
//  PetTankView.swift
//  Puck
//
//  The pet's tank: a strip across the top of the chat (and the editor, when
//  it is open). Draws the glass, never the pet -- the pet is rendered by
//  Puck.app's overlay window on top of this, which is what keeps there being
//  exactly one pet. See the 2026-08-22 spec.
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

    /// An unknown value means a key written by a future version, or a hand-
    /// edited default -- falling back beats refusing to draw the tank.
    private var background: TankBackground {
        TankBackground(rawValue: storedBackground) ?? .plain
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            background.backdrop(palette: palette)
            // The floor the pet stands on, kept in every theme.
            Rectangle()
                .fill(palette.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .frame(height: Self.height)
        .background(PaneFrameReporter(onChange: onFrameChange))
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

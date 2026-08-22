//
//  PetSizeSlider.swift
//  Puck
//
//  How big the pet is, in the toolbar above the island it is standing on.
//
//  It began on the island itself, at its top-right corner, and could not be
//  clicked: the window's toolbar covers that whole band whether or not
//  anything is drawn in it, so a control placed there takes no clicks at all.
//  Moving it up into the toolbar is what puts it where it looked like it was.
//
//  The pet's size is in Settings too. Settings is a window you open, look
//  away from the pet to use, and close; this is the same number with the pet
//  in view while it changes. Only the size on the island -- on the desktop
//  the slider in Settings still decides.
//

import SwiftUI

struct PetSizeSlider: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    /// Sends the height to pet-app, which is the process that actually
    /// resizes the pet.
    let onChange: (CGFloat) -> Void

    @AppStorage(PetTankView.petHeightStorageKey) private var storedHeight = PetTankView.defaultPetHeight
    /// The island's own height, read for its ceiling rather than to draw it:
    /// pet-app refuses a shelf shorter than the pet standing on it, which
    /// reads as the pet declining to come home. So the slider stops where the
    /// island does, and making the pet bigger means making the island taller
    /// first.
    @AppStorage(PetTankView.heightStorageKey) private var storedIslandHeight = Double(PetTankView.islandHeight)

    /// The tallest the pet may be right now: its own limit, or what the
    /// island can hold, whichever is lower.
    private var ceiling: Double {
        max(
            PetTankView.minimumPetHeight + 1,
            min(PetTankView.maximumPetHeight, storedIslandHeight - PetTankView.petHeadroom)
        )
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary.opacity(0.55))
            Slider(
                value: Binding(
                    get: { storedHeight },
                    set: { newValue in
                        storedHeight = newValue
                        onChange(CGFloat(newValue))
                    }
                ),
                in: PetTankView.minimumPetHeight...ceiling
            )
            .controlSize(.mini)
            .frame(width: 82)
        }
        // pet-app forgets the size when it quits, so the first window of the
        // next launch is where it finds out again.
        .onAppear { send(min(storedHeight, ceiling)) }
        // The island can be dragged shorter than the pet standing on it. The
        // pet gives way, since the alternative is a shelf it is refused from.
        .onChange(of: ceiling) { send(min(storedHeight, ceiling)) }
        .accessibilityLabel(Strings.text(.islandPetSize))
        .help(Strings.text(.islandPetSize))
    }

    private func send(_ height: Double) {
        storedHeight = height
        onChange(CGFloat(height))
    }
}

//
//  PetTankView.swift
//  Puck
//
//  The pet's island: a panel floating across the top of the chat (and the
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

    /// Where the toolbar's buttons end, in SwiftUI's global space, or nil
    /// when nothing has measured them. The island rises into the empty band
    /// past this point and stays clear of it before -- see IslandShape.
    var toolbarTrailingX: CGFloat?

    @Environment(\.clientPalette) private var palette

    /// Read straight from UserDefaults rather than through ClientWindowStore:
    /// nothing about the choice leaves this app (see TankBackground). It also
    /// keeps the two segments in step for free -- both read the same key, so
    /// changing it in one redraws the other.
    @AppStorage(TankBackground.storageKey) private var storedBackground = TankBackground.plain.rawValue

    /// Dragged from the island's bottom edge, and remembered. Stored as a
    /// Double because that is what @AppStorage keeps; clamped on read, so a
    /// value written by a future version with different limits cannot leave
    /// the pet in an island it does not fit in.
    @AppStorage(PetTankView.heightStorageKey) private var storedHeight = Double(PetTankView.islandHeight)

    /// What the drag is working from, so the gesture measures against where
    /// it started rather than accumulating rounding every frame.
    @State private var heightAtDragStart: CGFloat?

    private var islandHeight: CGFloat {
        min(max(CGFloat(storedHeight), Self.minimumIslandHeight), Self.maximumIslandHeight)
    }

    /// How tall the island opens at, and the pet's whole world while it is
    /// home.
    ///
    /// Insetting *this* is what once broke the move: the reported area is
    /// refused when it is shorter than the pet, so trimming 8pt off each end
    /// left 74 against an 80pt pet and the pet simply stayed on the desktop.
    /// The padding goes outside instead.
    static let islandHeight: CGFloat = 90

    /// The floor of the drag. Below this the pet no longer fits and the whole
    /// area is refused -- which looks like the pet refusing to come home, so
    /// the handle stops here rather than letting anyone find that out.
    static let minimumIslandHeight: CGFloat = 84

    /// Somewhere to stop. Past this the island is a pane rather than a shelf,
    /// and the conversation under it is what the window is for.
    static let maximumIslandHeight: CGFloat = 260

    /// Its own key, not the background's: how tall someone wants the shelf is
    /// not which mood they picked, and one changing should not reset the
    /// other.
    static let heightStorageKey = "Puck.islandHeight"

    /// How far the island floats from the window's own edges.
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 8

    /// The strip the island floats in.
    static func stripHeight(island: CGFloat) -> CGFloat { island + verticalInset * 2 }

    /// The same corners every floating panel in this window has.
    static let cornerRadius: CGFloat = ClientTheme.Metrics.panelCornerRadius

    /// How far the island reaches up into the toolbar's empty band. Short of
    /// filling it: the buttons beside it need air, and an island level with
    /// the traffic lights reads as the titlebar rather than as a panel.
    static let shoulderRise: CGFloat = 26

    /// Between the toolbar's last button and where the island starts to
    /// climb.
    static let shoulderGap: CGFloat = 14

    /// How far the part *under* the buttons rises too. The step down to it
    /// was the full shoulder, which left the buttons sitting in a trench;
    /// lifting the low end a little puts them on the island rather than
    /// beside it, without reaching the traffic lights' row.
    static let baseLift: CGFloat = 9

    /// The island itself: always the app's own ground, whatever mood is
    /// behind it. A pet standing on a picture reads as standing *in* it, so
    /// the backdrop stays behind the island rather than under the pet.
    private var island: some View {
        // Flat, on purpose. It carried a sheen and a specular edge for a
        // while, which read as glass -- and glass beside a plain sidebar and a
        // plain file list looked like one panel borrowed from another app.
        // What makes it a panel is its outline and the ground showing around
        // it, not a highlight.
        GeometryReader { proxy in
            let shape = IslandShape(
                cornerRadius: Self.cornerRadius,
                rise: Self.shoulderRise,
                shoulderStart: shoulderStart(in: proxy)
            )
            ZStack(alignment: .bottom) {
                shape.fill(palette.background)
                // The floor the pet stands on.
                Rectangle()
                    .fill(palette.textSecondary.opacity(0.25))
                    .frame(height: 1)
                    .clipShape(shape)
                shape.strokeBorder(palette.surfaceBorder.opacity(0.8), lineWidth: 1)
            }
            .compositingGroup()
            // Floating, so it sits above its surroundings rather than beside
            // them. Softer than a card's: the island is a shelf, not a dialog.
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        }
        .frame(height: islandHeight + Self.shoulderRise + Self.baseLift)
        // The grab area for resizing, on the edge it moves.
        .overlay(alignment: .bottom) { resizeHandle }
        // Reported from the island's floor rather than its outline: the pet's
        // world is the part it can stand in, and the raised shoulder is a
        // shape, not a room. A frame taken from the padded box would also let
        // it stand in the gap on either side.
        .overlay(alignment: .bottom) {
            Color.clear
                .frame(height: islandHeight)
                .background(PaneFrameReporter(onChange: onFrameChange))
                .allowsHitTesting(false)
        }
    }

    /// Where the shoulder begins in the island's own space: just past the
    /// toolbar's last button, with a gap so the two do not touch.
    ///
    /// Off the left edge when this segment starts to the right of the buttons
    /// already -- the editor's segment always does -- which raises the whole
    /// top edge. Off the right edge when nothing has measured the toolbar
    /// yet, which draws the plain rectangle it drew before.
    private func shoulderStart(in proxy: GeometryProxy) -> CGFloat {
        guard let toolbarTrailingX else { return .greatestFiniteMagnitude }
        return toolbarTrailingX + Self.shoulderGap - proxy.frame(in: .global).minX
    }

    /// Drag the bottom edge to make the shelf taller or shorter.
    ///
    /// On the island rather than in Settings: it is a size you judge by
    /// looking at it, and the pet is standing right there while you do.
    private var resizeHandle: some View {
        Capsule()
            .fill(palette.textSecondary.opacity(0.35))
            .frame(width: 34, height: 3)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .center)
            // A grab area taller than the grip itself: a 3pt target is a
            // pixel hunt, and the edge is where the pointer already is.
            .frame(height: 12)
            .contentShape(.rect)
            .onHover { inside in
                // The cursor says which way it moves before the drag starts.
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = heightAtDragStart ?? islandHeight
                        heightAtDragStart = start
                        // Down grows it: the handle is on the bottom edge, so
                        // the edge follows the pointer.
                        storedHeight = Double(
                            min(max(start + value.translation.height, Self.minimumIslandHeight), Self.maximumIslandHeight)
                        )
                    }
                    .onEnded { _ in heightAtDragStart = nil }
            )
            .accessibilityLabel(Strings.text(.islandResize))
            .help(Strings.text(.islandResize))
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
            // Bottom-aligned and then pulled up by exactly what it grew: the
            // strip keeps the height it always had, and the shoulder is drawn
            // outside it, in the toolbar's band. Laying the shoulder out
            // *inside* the strip would push the conversation down by the
            // height of a decoration.
            .frame(
                height: Self.stripHeight(island: islandHeight) + Self.shoulderRise + Self.baseLift,
                alignment: .bottom
            )
            .padding(.top, -(Self.shoulderRise + Self.baseLift))
            // The chosen mood goes around the island, not on it: the island
            // is ground, and what it floats in is the view behind it.
            .background(background.backdrop(palette: palette))
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

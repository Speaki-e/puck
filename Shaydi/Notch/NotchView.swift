//
//  NotchView.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  The notch's SwiftUI content: a small dark pill at rest, expanding on
//  hover into a row of toy-summon buttons -- byeolki, 2026-08-01: "boring
//  notch처럼 일반적인 다이내믹 아일랜드를 다는데, 이 일반적인 다이내믹
//  아일랜드를 펼치면 toy를 소환 시킬 수 있는 버튼이 생기게 해줘."
//
//  Owns its own hover-driven `isExpanded` state (for the pill's own shape
//  animation) and separately reports it via onExpandedChanged, so
//  NotchWindowController can resize the actual NSWindow to match -- the
//  same "SwiftUI drives its own visuals, AppKit host resizes around it"
//  split used elsewhere (e.g. TextInputBubbleView/TextInputBubbleWindow).
//

import SwiftUI

struct NotchView: View {
    /// Which toys are out when the notch is built. Rebuilt only once at
    /// launch (unlike the settings panel, this view isn't recreated per
    /// open), so toysOut is this view's own source of truth thereafter.
    var initialToysOut: Set<String> = []
    /// Returns the toys that are out *after* the toggle -- from what the toy
    /// box actually did, matching SettingsView's onToggleToy contract.
    var onToggleToy: ((Toy) -> Set<String>)?
    var onExpandedChanged: ((Bool) -> Void)?

    @State private var isExpanded = false
    @State private var toysOut: Set<String>

    init(
        initialToysOut: Set<String> = [],
        onToggleToy: ((Toy) -> Set<String>)? = nil,
        onExpandedChanged: ((Bool) -> Void)? = nil
    ) {
        self.initialToysOut = initialToysOut
        self.onToggleToy = onToggleToy
        self.onExpandedChanged = onExpandedChanged
        _toysOut = State(initialValue: initialToysOut)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                HStack(spacing: 20) {
                    ForEach(ToyCatalogue.all, id: \.name) { toy in
                        NotchToyButton(
                            artwork: ToyThumbnail.image(for: toy, boundingSide: 40),
                            tint: ToyPresentation.tint(for: toy),
                            isOut: toysOut.contains(toy.name)
                        ) {
                            guard let onToggleToy else { return }
                            toysOut = onToggleToy(toy)
                        }
                    }
                }
                .padding(.top, 18)
                .transition(.opacity)
            } else {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 44, height: 5)
                    .padding(.top, 9)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 26 : 12, style: .continuous)
                .fill(.black)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .onHover { hovering in
            isExpanded = hovering
            onExpandedChanged?(hovering)
        }
    }
}

/// One toy button in the expanded row -- a compact circular version of
/// Settings' ToyTile, sized for the notch rather than a grid tile.
private struct NotchToyButton: View {
    let artwork: NSImage?
    let tint: Color
    let isOut: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "questionmark")
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .padding(8)
            .background(tint.opacity(isOut ? 0.55 : 0.28), in: Circle())
            .overlay {
                Circle().strokeBorder(isOut ? tint : .clear, lineWidth: 2)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

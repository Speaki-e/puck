//
//  NotchView.swift
//  Puck
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  A boring.notch clone's headline widgets (Now Playing + battery) with the
//  toy-summon row added on top -- byeolki, 2026-08-01, after the first pass
//  shipped only a generic pill: "다이내믹 아일랜드 걍 Boring Notch
//  클론코딩을 기반으로 하고, 거기에 toy 꺼내는 것만 얹으라는 소리였는데".
//  2026-08-01 (later same day): actually cloned boring.notch's source
//  (github.com/TheBoredTeam/boring.notch) after byeolki flagged the result
//  as still "이상한데" -- the plain RoundedRectangle read as a floating
//  pill rather than an extension of the screen's own top edge. Now uses
//  NotchShape (the real concave/convex notch flare, ported from
//  boringNotch/components/Notch/NotchShape.swift) and a short hover
//  debounce (ported from ContentView.handleHover) instead of toggling
//  instantly.
//
//  Owns its own hover-driven `isExpanded` state (for the pill's own shape
//  animation) and separately reports it via onExpandedChanged, so
//  NotchWindowController can resize the actual NSWindow to match -- the
//  same "SwiftUI drives its own visuals, AppKit host resizes around it"
//  split used elsewhere (e.g. TextInputBubbleView/TextInputBubbleWindow).
//  Now Playing/battery values themselves live in NotchStatusStore, since
//  unlike toysOut (which this view drives itself) they change from outside
//  the view entirely.
//

import SwiftUI

struct NotchView: View {
    @ObservedObject var status: NotchStatusStore

    /// Which toys are out when the notch is built. Rebuilt only once at
    /// launch (unlike the settings panel, this view isn't recreated per
    /// open), so toysOut is this view's own source of truth thereafter.
    var initialToysOut: Set<String> = []
    /// Returns the toys that are out *after* the toggle -- from what the toy
    /// box actually did, matching SettingsView's onToggleToy contract.
    var onToggleToy: ((Toy) -> Set<String>)?
    var onExpandedChanged: ((Bool) -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    @State private var isExpanded = false
    @State private var toysOut: Set<String>
    @State private var pendingHoverWorkItem: DispatchWorkItem?

    init(
        status: NotchStatusStore,
        initialToysOut: Set<String> = [],
        onToggleToy: ((Toy) -> Set<String>)? = nil,
        onExpandedChanged: ((Bool) -> Void)? = nil,
        onTogglePlayPause: (() -> Void)? = nil,
        onNextTrack: (() -> Void)? = nil,
        onPreviousTrack: (() -> Void)? = nil
    ) {
        self.status = status
        self.initialToysOut = initialToysOut
        self.onToggleToy = onToggleToy
        self.onExpandedChanged = onExpandedChanged
        self.onTogglePlayPause = onTogglePlayPause
        self.onNextTrack = onNextTrack
        self.onPreviousTrack = onPreviousTrack
        _toysOut = State(initialValue: initialToysOut)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            } else {
                collapsedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            NotchShape(
                topCornerRadius: isExpanded ? NotchCornerRadii.expanded.top : NotchCornerRadii.collapsed.top,
                bottomCornerRadius: isExpanded ? NotchCornerRadii.expanded.bottom : NotchCornerRadii.collapsed.bottom
            )
            .fill(.black)
            // NotchWindow itself draws no shadow (see its own doc comment)
            // -- flush with the menu bar while collapsed, lifted only once
            // actually opened, matching boring.notch's own conditional
            // shadow in ContentView.
            .shadow(color: isExpanded ? .black.opacity(0.6) : .clear, radius: 8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .onHover(perform: handleHover)
    }

    /// A short delay before actually opening/closing, ported from
    /// boring.notch's ContentView.handleHover -- toggling `isExpanded`
    /// (and telling NotchWindowController to resize the real NSWindow)
    /// the instant the cursor merely crosses the pill made a cursor
    /// passing through on its way to a menu-bar item pop it open, and
    /// moving from the pill onto a widget inside it read as a flicker
    /// (momentary close immediately followed by reopen).
    private func handleHover(_ hovering: Bool) {
        pendingHoverWorkItem?.cancel()
        let delay = hovering ? 0.15 : 0.2
        let workItem = DispatchWorkItem {
            isExpanded = hovering
            onExpandedChanged?(hovering)
        }
        pendingHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// A grip capsule at rest -- unless something's playing, in which case a
    /// small music-note glyph stands in for it, boring.notch's own
    /// collapsed "live activity" treatment.
    private var collapsedContent: some View {
        Group {
            if status.nowPlaying != nil {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 44, height: 5)
            }
        }
        .padding(.top, 9)
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            if let nowPlaying = status.nowPlaying {
                NotchNowPlayingRow(
                    info: nowPlaying,
                    onTogglePlayPause: { onTogglePlayPause?() },
                    onNext: { onNextTrack?() },
                    onPrevious: { onPreviousTrack?() }
                )
            }

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

            if let battery = status.battery {
                NotchBatteryRow(status: battery)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// boring.notch's Now Playing widget: artwork, title/artist, and transport
/// controls, driven by whatever app is currently playing system-wide (see
/// NowPlayingMonitor/MediaRemoteBridge).
private struct NotchNowPlayingRow: View {
    let info: NowPlayingInfo
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            artwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = info.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                transportButton("backward.fill", action: onPrevious)
                transportButton(info.isPlaying ? "pause.fill" : "play.fill", action: onTogglePlayPause)
                transportButton("forward.fill", action: onNext)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var artwork: some View {
        Group {
            if let artworkData = info.artworkData, let image = NSImage(data: artworkData) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .overlay { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4)) }
            }
        }
    }

    private func transportButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

/// boring.notch's battery widget: percentage + a charging bolt when
/// plugged in, read straight from IOKit (see BatteryMonitor).
private struct NotchBatteryRow: View {
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.isCharging ? "battery.100.bolt" : batterySymbol)
                .font(.system(size: 11))
                .foregroundStyle(status.isCharging ? .green : .white.opacity(0.7))
            Text("\(status.percentage)%")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var batterySymbol: String {
        switch status.percentage {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<80: return "battery.50"
        case 80..<95: return "battery.75"
        default: return "battery.100"
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

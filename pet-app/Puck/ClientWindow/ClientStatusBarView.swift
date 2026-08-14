//
//  ClientStatusBarView.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- a persistent thin status bar, new UI
//  (docs/decisions.md). Reports the active workspace's *editor/project*
//  status -- deliberately not called "connection", since that term means
//  the pet-app<->workspace bridge socket elsewhere in this codebase and
//  this bar doesn't observe that.
//

import SwiftUI

/// Pure mapping, hoisted out of the view body so it's testable without
/// hosting a SwiftUI view.
func dotStatus(for availability: EditorAvailability) -> DotStatus {
    switch availability {
    case .noProject: return .idle
    case .ready: return .success
    case .unavailable: return .error
    }
}

struct ClientStatusBarView: View {
    let workspace: ClientWorkspace?
    let availability: EditorAvailability
    let palette: ClientPalette

    var body: some View {
        HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            StatusDotView(status: dotStatus(for: availability), palette: palette)
            // "일상 대화" matches ClientWindowStore.casualSessionTitle -- the
            // default workspace's own name, not an English placeholder
            // (every sibling string here is Korean, e.g. ConflictBannerView's
            // "디스크에서 파일이 변경됐습니다").
            Text(workspace?.name ?? "일상 대화")
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .frame(height: 22)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.surfaceBorder).frame(height: 1)
        }
    }
}

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

/// `/Users/x/dev/p` -> `~/dev/p`. Only at a path boundary, so `/Users/xyz`
/// isn't mangled by a home of `/Users/x`.
func abbreviatedPath(_ path: String, home: String) -> String {
    if path == home { return "~" }
    guard path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}

struct ClientStatusBarView: View {
    let workspace: ClientWorkspace?
    let availability: EditorAvailability
    let palette: ClientPalette

    /// Loaded fresh rather than threaded in from a store: this is the same
    /// config AgentSettingsView reads directly (AgentConfiguration.load()),
    /// and the model name changing means either a rebuild or an .env edit --
    /// neither of which this view needs to observe live.
    private var model: String {
        AgentConfiguration.load().model
    }

    // Matches ClientWindowStore.casualSessionTitle -- the
    // default workspace's own name, not an English placeholder (every
    // sibling string here is Korean, e.g. ConflictBannerView's "디스크에서
    // 파일이 변경됐습니다").
    private var projectLabel: String {
        guard let projectPath = workspace?.projectPath else { return workspace?.displayName ?? Strings.text(.chatCasualSession) }
        return abbreviatedPath(projectPath, home: NSHomeDirectory())
    }

    var body: some View {
        HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            StatusDotView(status: dotStatus(for: availability), palette: palette)
            Text(projectLabel)
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(palette.textSecondary)
            Rectangle()
                .fill(palette.surfaceBorder)
                .frame(width: 1, height: 10)
            Text(model)
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

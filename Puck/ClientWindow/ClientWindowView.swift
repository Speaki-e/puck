//
//  ClientWindowView.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window (plan/02_pet-app.md F13).
//
//  2026-08-01 design-system rebuild (byeolki: "기존 프론트엔드에서 고치기
//  보다는 프론트엔드를 처음부터 만드는 마음으로", after asking to tear down
//  the same-day Orbita-structured redesign entirely). ClientRailView's
//  popover-only rail becomes ClientSidebarView's real sidebar; theming
//  moves from Puck's system-wide AppAppearance to this window's own
//  ClientThemeStyle (light/dark/glass), injected as a SwiftUI environment
//  value so every nested view reads it without a threaded parameter.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ClientWindowView: View {
    @ObservedObject var store: ClientWindowStore
    @State private var showingSessionPopover = false

    private var palette: ClientPalette { store.themeStyle.palette }

    private var activeSession: ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }

    var body: some View {
        HStack(spacing: 0) {
            ClientSidebarView(store: store)

            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.5)
                mainArea
            }
            .frame(minWidth: 420)
            .background(palette.background)
        }
        .frame(minWidth: ClientTheme.Metrics.windowMinWidth, minHeight: ClientTheme.Metrics.windowMinHeight)
        .environment(\.clientPalette, palette)
        .preferredColorScheme(store.themeStyle.colorScheme)
    }

    /// Chat only. The embedded editor view (EditorWebView) is its own track
    /// and isn't hosted anywhere yet -- byeolki (2026-07-30): "에디터는 따로
    /// 할거라 토글 빼".
    @ViewBuilder
    private var mainArea: some View {
        if let activeSession {
            ChatView(session: activeSession, store: store)
        } else {
            Spacer()
        }
    }

    /// The current session's title, now a clickable pill instead of plain
    /// text -- byeolki shared 5 Figma references (2026-08-02, "얘네 참고해서
    /// 레이아웃 배치나 UI 손봐줄래") whose TopBar is a "New Chat ⌄" selector,
    /// not a label. The primary "새 채팅" action still lives in the sidebar
    /// (2026-08-01 rebuild); this adds a second, real way to switch sessions
    /// from wherever the transcript already has your attention, backed by
    /// the same session list the sidebar shows.
    private var topBar: some View {
        HStack {
            sessionSelector
            Spacer(minLength: 0)
            settingsButton
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.top, 28) // clears the transparent titlebar / traffic lights
        .padding(.bottom, ClientTheme.Metrics.spacingMedium)
    }

    /// byeolki's slothGPT reference (2026-08-02, "이거에 좀 더 맞춰봐") puts a
    /// settings gear in the TopBar's own icon group, not just behind Cmd+,.
    /// This calls the *same* real action PuckClient's menu already does --
    /// ClientMainMenu's "설정…" item resolves `Selector(("showSettings:"))`
    /// through the responder chain to AppDelegate rather than a typed
    /// `#selector` reference (PuckTests compiles ClientMainMenu.swift
    /// without AppDelegate, so a typed reference wouldn't build there); this
    /// button does the same nil-target send for the same reason, and reaches
    /// the same place since ClientWindowView is only ever actually shown by
    /// PuckClient's own AppDelegate.
    private var settingsButton: some View {
        Button {
            #if canImport(AppKit)
            NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
            #endif
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(palette.textSecondary)
                .padding(ClientTheme.Metrics.spacingSmall)
                .themedSurface(palette, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("설정")
        .help("설정")
    }

    private var sessionSelector: some View {
        Button {
            showingSessionPopover = true
        } label: {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Text(activeSession?.title ?? "")
                    .font(ClientTheme.Typography.workspaceName)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            .themedSurface(palette, in: ClientTheme.Shapes.row)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("세션 전환")
        .accessibilityValue(activeSession?.title ?? "")
        .help("세션 전환")
        .popover(isPresented: $showingSessionPopover, arrowEdge: .bottom) {
            TopBarSessionPopoverContent(store: store, onSelect: { showingSessionPopover = false })
        }
    }
}

private struct TopBarSessionPopoverContent: View {
    @ObservedObject var store: ClientWindowStore
    let onSelect: () -> Void
    @Environment(\.clientPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.sessions(in: store.activeWorkspaceId)) { session in
                let isActive = session.id == store.activeSessionId
                Button {
                    store.activeSessionId = session.id
                    onSelect()
                } label: {
                    HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                        Image(systemName: "message.fill")
                            .font(.caption)
                            .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
                            .frame(width: 18)
                        Text(session.title)
                            .font(ClientTheme.Typography.sessionTitle)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                .background(isActive ? palette.accent.opacity(0.14) : Color.clear, in: ClientTheme.Shapes.row)
            }

            Button {
                store.requestNewSession(title: "새 채팅", in: store.activeWorkspaceId)
                onSelect()
            } label: {
                Label("새 채팅", systemImage: "plus")
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(palette.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        }
        .padding(ClientTheme.Metrics.spacingSmall)
        .frame(width: 240)
    }
}

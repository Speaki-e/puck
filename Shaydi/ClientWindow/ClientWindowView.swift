//
//  ClientWindowView.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window (plan/02_pet-app.md F13).
//
//  2026-08-01 design-system rebuild (byeolki: "기존 프론트엔드에서 고치기
//  보다는 프론트엔드를 처음부터 만드는 마음으로", after asking to tear down
//  the same-day Orbita-structured redesign entirely). ClientRailView's
//  popover-only rail becomes ClientSidebarView's real sidebar; theming
//  moves from Shaydi's system-wide AppAppearance to this window's own
//  ClientThemeStyle (light/dark/glass), injected as a SwiftUI environment
//  value so every nested view reads it without a threaded parameter.
//

import SwiftUI

struct ClientWindowView: View {
    @ObservedObject var store: ClientWindowStore

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

    /// Minimal -- the primary "새 채팅" action lives in the sidebar now
    /// (2026-08-01 rebuild), so this is just the current session's title.
    private var topBar: some View {
        Text(activeSession?.title ?? "")
            .font(ClientTheme.Typography.workspaceName)
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
            .padding(.top, 28) // clears the transparent titlebar / traffic lights
            .padding(.bottom, ClientTheme.Metrics.spacingMedium)
    }
}

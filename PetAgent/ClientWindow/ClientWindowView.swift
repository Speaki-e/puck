//
//  ClientWindowView.swift
//  PetAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window: sidebar (workspace switcher +
//  session list) on the left, the chat transcript on the right
//  (plan/02_pet-app.md F13). Docked beside the pinned character when summoned
//  via Option+Shift+Space.
//

import SwiftUI

struct ClientWindowView: View {
    @ObservedObject var store: ClientWindowStore

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private var activeSession: ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }

    var body: some View {
        // HSplitView, not HStack + Divider: the divider is then a real
        // draggable splitter (byeolki: "그 사이드 바나 그런 거 전부 조절
        // 가능하게 늘리고 줄이고"). It's AppKit's NSSplitView underneath, so
        // the drag behaviour is the system's, not something hand-rolled.
        HSplitView {
            ClientSidebarView(store: store)

            ZStack(alignment: .top) {
                mainArea
                // The header floats *over* the content rather than sitting in
                // a bar above it: glass has to have something behind it to
                // refract, and a divider-separated strip gives it nothing.
                header
            }
            .frame(minWidth: 420)
            // A material, not a flat color -- every glass surface in this
            // pane is reading from what's behind it.
            .background(VisualEffectBackground(material: .contentBackground))
        }
        .frame(minWidth: 640, minHeight: 420)
        .preferredColorScheme(store.appearance.colorScheme)
    }

    /// Chat only. The embedded editor view (EditorWebView) is its own track
    /// and isn't hosted anywhere yet -- byeolki (2026-07-30): "에디터는 따로
    /// 할거라 토글 빼".
    @ViewBuilder
    private var mainArea: some View {
        if let activeSession {
            ChatView(session: activeSession, store: store, topInset: Self.headerHeight)
        } else {
            Spacer()
        }
    }

    /// How far the content has to be pushed down to clear the floating
    /// header (its own height plus the window's transparent titlebar strip).
    private static let headerHeight: CGFloat = 64

    private var header: some View {
        GlassGroup(spacing: ClientTheme.Metrics.spacingSmall) {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeSession?.title ?? "")
                        .font(ClientTheme.Typography.workspaceName)
                    Text(activeWorkspace?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(ClientTheme.Colors.secondaryText)
                }
                // No glass behind the title (byeolki, 2026-07-30): a label
                // that never moves or reacts doesn't need a surface, and it
                // read as a floating chip for no reason.
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        }
        .padding(.top, 28) // clears the transparent titlebar / traffic lights
    }
}

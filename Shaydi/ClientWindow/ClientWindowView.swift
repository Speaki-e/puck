//
//  ClientWindowView.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window (plan/02_pet-app.md F13).
//  Docked beside the pinned character when summoned via Option+Shift+Space.
//
//  2026-08-01 restructure (byeolki: "Orbita로 해봐봐", after "아예 갈아엎을
//  순 없는거냐" -- the prior pass only changed colors on the same skeleton,
//  which read as no change at all): the resizable workspace/session sidebar
//  is gone. Orbita GPT's own shape is a slim icon rail plus a real top bar
//  with the primary action as a filled pill -- ClientRailView and `topBar`
//  below are that structure, not just its palette.
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
        HStack(spacing: 0) {
            ClientRailView(store: store)

            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.5)
                mainArea
            }
            .frame(minWidth: 420)
            // A material, not a flat color -- every glass surface in this
            // pane is reading from what's behind it.
            .background(VisualEffectBackground(material: .contentBackground))
        }
        .frame(minWidth: 640, minHeight: 420)
        .preferredColorScheme(store.appearance.colorScheme)
        // See SettingsView's identical `.id` -- same SwiftUI
        // `.preferredColorScheme(nil)` diffing quirk applies here too.
        .id(store.appearance)
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

    /// A real row now, not a floating glass capsule over the transcript --
    /// Orbita's top bar is opaque and always occupies its own space, with the
    /// one filled pill (there: "New Chat") as its single loud element.
    private var topBar: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            VStack(alignment: .leading, spacing: 1) {
                Text(activeSession?.title ?? "")
                    .font(ClientTheme.Typography.workspaceName)
                if let workspaceName = activeWorkspace?.name, workspaceName != activeSession?.title {
                    Text(workspaceName)
                        .font(.caption)
                        .foregroundStyle(ClientTheme.Colors.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Button {
                store.requestNewSession(title: "새 채팅", in: store.activeWorkspaceId)
            } label: {
                Label("새 채팅", systemImage: "square.and.pencil")
                    .font(ClientTheme.Typography.workspaceName)
                    .foregroundStyle(ClientTheme.Colors.onAccent)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    .glassControl(in: Capsule(), tint: ClientTheme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.top, 28) // clears the transparent titlebar / traffic lights
        .padding(.bottom, ClientTheme.Metrics.spacingMedium)
    }
}

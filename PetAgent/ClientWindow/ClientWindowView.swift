//
//  ClientWindowView.swift
//  PetAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window: sidebar (workspace switcher +
//  session list) on the left, chat <-> embedded editor view on the right
//  (plan/02_pet-app.md F13). Docked beside the pinned character when summoned
//  via Option+Shift+Space.
//

import SwiftUI

private enum MainAreaMode: String, CaseIterable {
    case chat = "채팅"
    case editor = "에디터"
}

struct ClientWindowView: View {
    @ObservedObject var store: ClientWindowStore
    @State private var mode: MainAreaMode = .chat

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private var activeSession: ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }

    var body: some View {
        HStack(spacing: 0) {
            ClientSidebarView(store: store)
                .frame(width: 220)

            Divider()

            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(MainAreaMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                // project_path 없는 워크스페이스는 에디터 뷰가 없으니 그 상태에선
                // 채팅 뷰로 강제 — F13: "project_path 없는 워크스페이스는 에디터
                // 버튼이 비활성화".
                .disabled(activeWorkspace?.projectPath == nil)

                Divider()

                switch mode {
                case .chat:
                    if let activeSession {
                        ChatView(session: activeSession, store: store)
                    } else {
                        Spacer()
                    }
                case .editor:
                    if let url = activeWorkspace?.editorViewURL {
                        EditorWebView(url: url)
                    } else {
                        EditorUnavailableView()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onChange(of: store.activeWorkspaceId) {
            // Switching to a workspace with no editor view falls back to chat
            // rather than showing a stale editor for the previous workspace.
            if activeWorkspace?.projectPath == nil { mode = .chat }
        }
    }
}

//
//  ClientWindowView.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window (plan/02_pet-app.md F13).
//
//  Chat rebuild (2026-08-13, docs/decisions.md): sidebar, top bar, and
//  transcript all moved into ClientChatWebView (React/Tailwind/shadcn) --
//  this view is now just that web view, plus the native EditorWebView pane
//  when the (web-driven) editor toggle is on. ClientPalette/ClientTheme
//  still theme the settings window and window chrome, but no longer this
//  view's own content.
//

import SwiftUI

struct ClientWindowView: View {
    @ObservedObject var store: ClientWindowStore
    let chatBridge: ClientChatBridge
    @State private var isEditorOpen = false

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        Group {
            if isEditorOpen, let editorURL = activeWorkspace?.editorViewURL {
                HSplitView {
                    ClientChatWebView(bridge: chatBridge)
                        .frame(minWidth: 320, idealWidth: 420)
                    EditorWebView(workspaceId: store.activeWorkspaceId, url: editorURL)
                        .frame(minWidth: 360)
                }
            } else {
                ClientChatWebView(bridge: chatBridge)
            }
        }
        .frame(minWidth: ClientTheme.Metrics.windowMinWidth, minHeight: ClientTheme.Metrics.windowMinHeight)
        .onAppear {
            chatBridge.setEditorOpenChangeHandler { isOpen in isEditorOpen = isOpen }
        }
    }
}

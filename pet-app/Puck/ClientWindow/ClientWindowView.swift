//
//  ClientWindowView.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window (plan/02_pet-app.md F13).
//
//  Chat rebuild (2026-08-13, docs/decisions.md): sidebar, top bar, and
//  transcript all moved into ClientChatWebView (React/Tailwind/shadcn) --
//  this view is now just that web view, plus the native EditorPaneView pane
//  when the (web-driven) editor toggle is on.
//
//  Native editor pane (F13 continued): EditorPaneView reads files itself via
//  WorkspaceFileService instead of loading a URL workspace serves, so this
//  view now also injects clientPalette into the environment -- ClientPalette/
//  ClientTheme otherwise only themed the settings window, and EditorPaneView's
//  views need the active theme the same way that window does.
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
        VStack(spacing: 0) {
            Group {
                if isEditorOpen, let availability = activeWorkspace?.editorAvailability {
                    HSplitView {
                        ClientChatWebView(bridge: chatBridge)
                            .frame(minWidth: 320, idealWidth: 420)
                        EditorPaneView(
                            workspaceId: store.activeWorkspaceId,
                            availability: availability,
                            onUnavailable: { store.refreshEditorAvailability(forWorkspace: store.activeWorkspaceId) }
                        )
                        .frame(minWidth: 360)
                    }
                } else {
                    ClientChatWebView(bridge: chatBridge)
                }
            }
            ClientStatusBarView(
                workspace: activeWorkspace,
                availability: activeWorkspace?.editorAvailability ?? .noProject,
                palette: store.themeStyle.palette
            )
        }
        .frame(minWidth: ClientTheme.Metrics.windowMinWidth, minHeight: ClientTheme.Metrics.windowMinHeight)
        .environment(\.clientPalette, store.themeStyle.palette)
        .onAppear {
            chatBridge.setEditorOpenChangeHandler { isOpen in isEditorOpen = isOpen }
        }
    }
}

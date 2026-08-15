//
//  ClientWindowView.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The "Claude Desktop"-style client window (plan/02_pet-app.md F13).
//
//  Chat rebuild (2026-08-13): sidebar, top bar and transcript moved into
//  ClientChatWebView (React/Tailwind/shadcn). Undone 2026-08-15: they are
//  ChatPaneView now, native, and the web bundle is gone. The reason web was
//  chosen -- iterating fast toward a bespoke shadcn look -- stopped applying
//  when the target became stock Apple components. See
//  docs/superpowers/specs/2026-08-15-native-chat-design.md.
//
//  The editor toggle is this view's own state again rather than something the
//  web view drove through a bridge handler, which is also what let it grow a
//  keyboard shortcut (⇧⌘E).
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
    @State private var isEditorOpen = false

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isEditorOpen, let availability = activeWorkspace?.editorAvailability {
                    HSplitView {
                        ChatPaneView(store: store, isEditorOpen: $isEditorOpen)
                            .frame(minWidth: 480, idealWidth: 620)
                        EditorPaneView(
                            workspaceId: store.activeWorkspaceId,
                            availability: availability,
                            onUnavailable: { store.refreshEditorAvailability(forWorkspace: store.activeWorkspaceId) }
                        )
                        .frame(minWidth: 360)
                    }
                } else {
                    ChatPaneView(store: store, isEditorOpen: $isEditorOpen)
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
        // Closing the editor when the active workspace can't show one: the
        // toggle is sticky across workspace switches, and a pane left open on
        // a chat-only workspace would render its empty state for no reason.
        .onChange(of: store.activeWorkspaceId) {
            if activeWorkspace?.canOpenEditor != true { isEditorOpen = false }
        }
    }
}

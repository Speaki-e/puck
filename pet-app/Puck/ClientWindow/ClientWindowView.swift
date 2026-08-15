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
    @State private var editor: EditorPresentation = .hidden

    /// The window cannot go narrower than what it is currently showing. Two
    /// panes need more room than one, so the floor moves with the toggle
    /// rather than being a single compromise that is wrong for both.
    private var minimumWindowWidth: CGFloat {
        // Only the split needs the wider floor. Detached, the editor carries
        // its own window and this one goes back to being a chat window.
        editor.isAttached ? ClientTheme.Metrics.windowMinWidthWithEditor : ClientTheme.Metrics.windowMinWidth
    }

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if editor.isAttached, let availability = activeWorkspace?.editorAvailability {
                    HSplitView {
                        // Each is the real minimum of what it contains, and
                        // windowMinWidthWithEditor is their sum -- rather than
                        // the other way round, which is how the editor came to
                        // declare 360 while needing 540 and got its file tree
                        // clipped at the smallest window.
                        ChatPaneView(store: store, editor: $editor)
                            .frame(minWidth: 560, idealWidth: 620)
                        EditorPaneView(
                            workspaceId: store.activeWorkspaceId,
                            availability: availability,
                            onUnavailable: { store.refreshEditorAvailability(forWorkspace: store.activeWorkspaceId) }
                        )
                        .frame(minWidth: 540)
                    }
                } else {
                    ChatPaneView(store: store, editor: $editor)
                }
            }
            ClientStatusBarView(
                workspace: activeWorkspace,
                availability: activeWorkspace?.editorAvailability ?? .noProject,
                palette: store.themeStyle.palette
            )
        }
        // No .frame(minWidth:) here: sizingOptions = [] on the hosting
        // controller means SwiftUI's minimum never becomes a real resize
        // limit anyway (see PuckClient's AppDelegate), and stating it twice
        // is how the two drifted apart before. The window owns its floor.
        .background(WindowMinimumSize(width: minimumWindowWidth, height: ClientTheme.Metrics.windowMinHeight))
        .detachedEditorWindow(
            presentation: $editor,
            workspaceId: store.activeWorkspaceId,
            availability: activeWorkspace?.editorAvailability ?? .noProject,
            palette: store.themeStyle.palette,
            onUnavailable: { store.refreshEditorAvailability(forWorkspace: store.activeWorkspaceId) }
        )
        .environment(\.clientPalette, store.themeStyle.palette)
        // Closing the editor when the active workspace can't show one: the
        // toggle is sticky across workspace switches, and a pane left open on
        // a chat-only workspace would render its empty state for no reason.
        .onChange(of: store.activeWorkspaceId) {
            if activeWorkspace?.canOpenEditor != true { editor = .hidden }
        }
        // The agent asked for a file to be on screen. Only obeyed when the
        // workspace can actually show one -- a chat-only workspace would open
        // an empty pane and then have to close it again.
        .onChange(of: store.editorRevealRequests) {
            // Already detached: the file is on screen, in the other window.
            // Pulling it into the split would move the editor out from under
            // whoever put it where it is.
            guard activeWorkspace?.canOpenEditor == true, editor != .detached else { return }
            editor = .attached
        }
    }
}

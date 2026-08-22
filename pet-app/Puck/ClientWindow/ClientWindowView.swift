//
//  ClientWindowView.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
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
    /// Redraws this view when the UI language changes.
    ///
    /// One observer at the root is not enough, which is worth stating because
    /// it looks like it should be: SwiftUI skips re-running a child whose own
    /// inputs are unchanged, and a `Strings` lookup inside `body` is not an
    /// input. Every view that resolves a string carries this property for
    /// that reason.
    @ObservedObject private var localization = Localization.shared
    @State private var editor: EditorPresentation = .hidden
    /// Whether the code column was showing when the window last closed.
    ///
    /// Remembered for the same reason the terminal's state is: someone who
    /// works with the files beside the conversation wants them there the next
    /// morning, and closing the app is not them putting the pane away. Only
    /// attached-or-not: a detached editor is a window, and windows are
    /// restored by whoever opens them, not by a flag.
    @AppStorage("Puck.editorAttached") private var editorWasAttached = false
    /// Resolved here rather than inside the editor, because the two halves it
    /// used to hold now live in different parts of the window: the file list
    /// on the right, a file's contents beside the conversation. One owner
    /// keeps them looking at the same project.
    @State private var editorStore: EditorPaneStore?
    /// The active project's git status, for the footer. Its own reader rather
    /// than the explorer's: the footer is on screen whether or not the
    /// explorer is, and a status that only existed while a pane was open
    /// would be a footer that emptied when you collapsed something unrelated.
    @StateObject private var git = GitStatusModel()

    /// The window cannot go narrower than what it is currently showing. Two
    /// panes need more room than one, so the floor moves with the toggle
    /// rather than being a single compromise that is wrong for both.
    private var minimumWindowWidth: CGFloat {
        // Only the split needs the wider floor. Detached, the editor carries
        // its own window and this one goes back to being a chat window.
        // Reserved for the split even before a file is open. Whether one is
        // open is a published property of a store this view holds in `State`,
        // which does not invalidate on it -- so a floor that tracked it would
        // lag exactly when it mattered, and the window would squeeze the
        // moment the code column appeared.
        editor.isAttached ? ClientTheme.Metrics.windowMinWidthWithCode : ClientTheme.Metrics.windowMinWidth
    }

    /// Attaches the store for the active workspace, or clears it when that
    /// workspace has no project to show. Idempotent for the one already
    /// attached: the pool keeps a store per workspace alive for the process's
    /// life, so switching back and forth costs nothing and keeps open tabs.
    private func syncEditorStore() {
        guard case .ready(let root) = activeWorkspace?.editorAvailability else {
            editorStore = nil
            return
        }
        guard editorStore?.workspaceId != store.activeWorkspaceId else { return }
        do {
            editorStore = try EditorPaneStorePool.shared.store(
                forWorkspace: store.activeWorkspaceId,
                root: root,
                onRootChanged: { store.refreshEditorAvailability(forWorkspace: store.activeWorkspaceId) }
            )
        } catch {
            editorStore = nil
            store.refreshEditorAvailability(forWorkspace: store.activeWorkspaceId)
        }
    }

    /// Reopens the code column if it was open when the app last quit.
    ///
    /// Asked again on every workspace switch, not only at launch: at launch
    /// the window is showing whichever workspace was active, and the one that
    /// can open an editor may be a different one -- so a single try on appear
    /// restored nothing for the case that matters most.
    private func restoreEditorIfWanted() {
        guard editorWasAttached, editor == .hidden, activeWorkspace?.canOpenEditor == true else { return }
        editor = .attached
    }

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if editor.isAttached, let editorStore {
                    HSplitView {
                        // The conversation keeps the middle and the widest
                        // minimum: it is what the window is for, and a file
                        // opened from the explorer splits *this* column
                        // rather than replacing it.
                        ChatPaneView(store: store, editor: $editor, editorStore: editorStore, activeBranch: git.status?.branch)
                            .frame(minWidth: 520)
                            // Free width goes here, not to the file list.
                            // Without it, collapsing the session sidebar grew
                            // the explorer -- the one column that gains
                            // nothing from being wider.
                            .layoutPriority(1)
                        // A file list needs room for names, not for a second
                        // editor: the code it opens goes beside the
                        // conversation instead.
                        FileExplorerPane(store: editorStore)
                            .frame(minWidth: 170, idealWidth: 200, maxWidth: 280)
                    }
                } else if editor.isAttached, let availability = activeWorkspace?.editorAvailability {
                    // Attached with no store: this workspace has no project,
                    // or its root went away. The empty state says which.
                    HSplitView {
                        ChatPaneView(store: store, editor: $editor, editorStore: nil, activeBranch: git.status?.branch)
                            .frame(minWidth: 520)
                            .layoutPriority(1)
                        EditorEmptyStateView(availability: availability)
                            .frame(minWidth: 170, idealWidth: 200, maxWidth: 280)
                    }
                } else {
                    ChatPaneView(store: store, editor: $editor, editorStore: nil, activeBranch: git.status?.branch)
                }
            }
            ClientStatusBarView(
                workspace: activeWorkspace,
                availability: activeWorkspace?.editorAvailability ?? .noProject,
                palette: store.themeStyle.palette,
                git: git.status
            )
        }
        // No .frame(minWidth:) here: sizingOptions = [] on the hosting
        // controller means SwiftUI's minimum never becomes a real resize
        // limit anyway (see PuckClient's AppDelegate), and stating it twice
        // is how the two drifted apart before. The window owns its floor.
        // One ground for the whole window -- the blurred desktop, tinted by
        // the theme. Painted here rather than per column so the toolbar strip
        // and the gap under the traffic lights are part of it, which is what
        // stops the top reading as a band of unrelated chrome.
        .background {
            WindowBackdrop()
                .overlay(store.themeStyle.palette.background.opacity(ClientTheme.Metrics.windowTint))
                .ignoresSafeArea()
        }
        // Hidden, not tinted: AppKit's own toolbar material would sit on top
        // of the backdrop and put the band back.
        .toolbarBackground(.hidden, for: .windowToolbar)
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
            syncEditorStore()
            restoreEditorIfWanted()
        }
        .onAppear {
            syncEditorStore()
            restoreEditorIfWanted()
        }
        .task(id: activeWorkspace?.projectPath) {
            await git.reload(projectPath: activeWorkspace?.projectPath)
        }
        // After the agent has written something, not only when the project
        // changes: the count in the footer is the answer to "what did that
        // turn touch".
        .onChange(of: editorStore?.treeRevision) {
            Task { await git.reload(projectPath: activeWorkspace?.projectPath) }
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
        // Hidden or detached, the editor's segment is no longer part of this
        // window's tank -- a detached editor is a different window, and a
        // hidden one has no strip on screen at all.
        .onChange(of: editor) {
            // Only the two states this remembers. Detaching leaves the flag
            // where it was, so re-attaching later lands where you left it.
            if editor != .detached { editorWasAttached = editor.isAttached }
            guard !editor.isAttached else { return }
            store.setTankSegment(nil, for: .editor)
        }
    }
}

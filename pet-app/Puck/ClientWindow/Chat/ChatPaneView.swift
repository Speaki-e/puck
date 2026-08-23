//
//  ChatPaneView.swift
//  Puck
//
//  The chat window's whole UI, native again (2026-08-15) -- replaces
//  ClientChatWebView and the chat-web bundle behind it. See
//  docs/superpowers/specs/2026-08-15-native-chat-design.md.
//
//  Reads ClientWindowStore/ChatSession directly. Those were always the source
//  of truth; chat-web was a second consumer of them over a hand-mirrored JSON
//  bridge, and removing it removes the mirror rather than any state.
//

import AppKit
import SwiftUI

struct ChatPaneView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: ClientWindowStore
    /// Where the editor is showing, owned by ClientWindowView -- the toggle
    /// lives in this view's toolbar but the split is its parent's.
    @Binding var editor: EditorPresentation
    /// The project's files, when this workspace has one. Held by
    /// ClientWindowView; this view only splits its detail around it.
    var editorStore: EditorPaneStore?
    /// The active project's branch, passed through to the sidebar -- see
    /// ChatSidebarView.activeBranch.
    var activeBranch: String?
    /// Which of the right column's three lists is showing, when that column
    /// is on screen. In the toolbar because the band above it was empty --
    /// the whole width of it, over the one column with no chrome of its own.
    var explorerTab: Binding<ExplorerTab>?

    /// Where the toolbar's last button ends, measured rather than assumed --
    /// the island climbs into the empty band past it, and a hard-coded x
    /// would be wrong the first time a button was added. Nil until the
    /// toolbar has laid itself out.
    /// Where the toolbar's last button ends. Owned by the window rather than
    /// by this view: the island is drawn in both columns now, and the strip
    /// over the file list has to climb into the same band this one does.
    @Binding var toolbarTrailingX: CGFloat?
    /// The same key CodeSplitView stores it under. The toggle is in the
    /// window's toolbar as well as in the code column's own strip, because
    /// the column is what it opens: a shortcut that only exists once the
    /// column is showing cannot be the way you show it -- with the column
    /// closed the key press fell through to the composer as a stray backtick.
    @AppStorage(TerminalSection.openStorageKey) private var isTerminalOpen = false

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store, activeBranch: activeBranch)
                // Allowed to compress to 180: at the 960pt window minimum the
                // three panes (sidebar, chat, editor) are already tight, and a
                // sidebar that refuses to give any width back is what squeezed
                // the composer's placeholder onto two lines. A capped maximum
                // stops it eating the chat when the window is wide instead.
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = activeSession {
            // Above `conversation`, not inside the chat column: the tank is a
            // strip across the whole detail area, and it was one before the
            // code column existed. Putting it inside would shrink the pet's
            // home to the chat's width the moment a file is opened.
            VStack(spacing: 0) {
                PetTankView(
                    onFrameChange: { store.setTankSegment($0, for: .chat) },
                    onPetHeightChange: { store.setPetIslandHeight($0) },
                    toolbarTrailingX: toolbarTrailingX
                )
                conversation(session)
            }
            .navigationTitle(session.displayTitle)
            .navigationSubtitle(activeWorkspace?.displayName ?? "")
            .toolbar { toolbarContent }
        } else {
            // Only reachable if the active ids point at a session that no
            // longer exists; the store always seeds one per workspace.
            ContentUnavailableView(Strings.text(.chatSelectAConversation), systemImage: "bubble.left.and.bubble.right")
        }
    }

    /// The conversation, and beside it the file that was opened from the
    /// explorer. Split rather than swapped: the reason to look at a file is
    /// usually what was just said about it, and a layout that shows one by
    /// hiding the other makes you choose between them.
    @ViewBuilder
    private func conversation(_ session: ChatSession) -> some View {
        if let editorStore {
            // Through a view that observes the store rather than deciding
            // here: whether a file is open is one of its published
            // properties, and a plain `var` is not an input SwiftUI watches.
            // Read straight from this body, clicking a file in the explorer
            // highlighted the row and split nothing.
            ConversationSplit(store: editorStore) { chatColumn(session) }
        } else {
            chatColumn(session)
        }
    }

    private func chatColumn(_ session: ChatSession) -> some View {
        // No ground of its own: the window's backdrop is the ground, and a
        // column painting over it would be the one opaque rectangle in a
        // translucent window.
        chatStack(session)
    }

    private func chatStack(_ session: ChatSession) -> some View {
        VStack(spacing: 0) {
            ChatTranscriptView(session: session) { approved in
                store.respondToPendingApproval(in: session, approved: approved)
            }
            // No rule above the composer: the box already has an edge of its
            // own, and a full-width line over it cut the window in two.
            ChatInputBar(
                isRunning: session.isRunning,
                onSend: { text, attachments in
                    store.sendMessage(text, source: .text, attachments: attachments.isEmpty ? nil : attachments)
                },
                onCancel: { store.cancelActiveRun() },
                isListening: store.isVoiceListening,
                onVoiceListening: { store.setVoiceListening($0) }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading, and the first thing in the window's toolbar: the only other
        // way to start a chat is the icon in a sidebar section header, which
        // is per-workspace and therefore small and easy to miss. This one acts
        // on the workspace already being looked at, which is what "새 대화"
        // means nearly every time, and ⌘N is where every Mac app puts it.
        ToolbarItem(placement: .navigation) {
            Button {
                store.requestNewSession(title: ChatSession.placeholderTitle, in: store.activeWorkspaceId)
            } label: {
                Label(Strings.text(.chatNewSession), systemImage: "square.and.pencil")
            }
            .help(newSessionHelp)
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem {
            Button {
                editor = editor.toggled
            } label: {
                Label(Strings.text(.chatEditor), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .disabled(activeWorkspace?.canOpenEditor != true || editor == .detached)
            .help(editorButtonHelp)
            // A keyboard shortcut, which the web toggle never had: the button
            // was the only way in, so the pane could not be opened without a
            // mouse (and could not be driven by automation at all).
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        // No detach button, and no ⌘⇧D with it. The toolbar carried two
        // buttons for the same column and this was the one nobody pressed.
        // DetachedEditorWindow stays wired up: nothing offers detaching now,
        // but a window that is already out has to be able to come back.
        ToolbarItem {
            Button {
                guard activeWorkspace?.canOpenEditor == true else { return }
                isTerminalOpen.toggle()
                if isTerminalOpen, editor == .hidden { editor = .attached }
            } label: {
                Label(Strings.text(.terminalToggle), systemImage: "terminal")
            }
            .disabled(activeWorkspace?.canOpenEditor != true)
            .keyboardShortcut("`", modifiers: .control)
            .help(Strings.text(.terminalToggle))
        }
        if let explorerTab {
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: explorerTab) {
                    ForEach(ExplorerTab.allCases) { tab in
                        Image(systemName: tab.symbolName)
                            .help(tab.displayName)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Rebuilt on a language change: NSSegmentedControl keeps the
                // titles it was built with, so its accessibility labels would
                // stay in the old language.
                .id(localization.language)
                .help(Strings.text(.explorerTabFiles))
            }
        }
        ToolbarItem {
            Button {
                NSApp.sendAction(NSSelectorFromString("showSettings:"), to: nil, from: nil)
            } label: {
                Label(Strings.text(.chatSettings), systemImage: "gearshape")
            }
            // The last button in the group, so its trailing edge is where the
            // toolbar ends and the island's shoulder may begin.
            .background(GlobalFrameReporter { toolbarTrailingX = $0.maxX })
        }

    }

    /// Names the workspace the chat would be created in -- "this workspace"
    /// only when it has no name to give.
    private var newSessionHelp: String {
        let workspace = activeWorkspace?.displayName ?? Strings.text(.chatThisWorkspace)
        return "\(workspace) · \(Strings.text(.chatNewSession))"
    }

    private var editorButtonHelp: String {
        guard activeWorkspace?.canOpenEditor == true else { return Strings.text(.chatNoProjectLinked) }
        return Strings.text(editor == .detached ? .chatEditorInSeparateWindow : .chatEditor)
    }

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private var activeSession: ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }
}

/// The conversation, and beside it the file the explorer opened.
///
/// Split rather than swapped: the reason to look at a file is usually what
/// was just said about it, and a layout that shows one by hiding the other
/// makes you choose between them.
private struct ConversationSplit<Chat: View>: View {
    @ObservedObject var store: EditorPaneStore
    @ViewBuilder var chat: Chat

    /// The shell under the code. Read here rather than only inside
    /// CodeSplitView because it has to be reachable with no file open: the
    /// terminal used to live inside the code column, so asking for one before
    /// opening a file toggled a setting and showed nothing.
    @AppStorage(TerminalSection.openStorageKey) private var isTerminalOpen = false

    /// Put away rather than closed. The tab stays open, so coming back to the
    /// file does not mean finding it again -- and opening another one from
    /// the explorer brings the column back, which is what the click means.
    @State private var isCollapsed = false

    var body: some View {
        Group {
            if store.activeTabPath == nil, !isTerminalOpen {
                chat
            } else if store.activeTabPath != nil, isCollapsed, !isTerminalOpen {
                HStack(spacing: 0) {
                    chat
                    Divider()
                    reopenHandle
                }
            } else {
                HSplitView {
                    chat.frame(minWidth: 320)
                    VStack(spacing: 0) {
                        if store.activeTabPath != nil, !isCollapsed {
                            // Putting the code away puts the shell under it
                            // away too: it is the same column, and a terminal
                            // left alone in it is a column holding a shell
                            // nobody asked to keep.
                            CodeSplitView(store: store) {
                                isCollapsed = true
                                isTerminalOpen = false
                            }
                                .frame(maxHeight: .infinity)
                        } else if store.activeTabPath != nil {
                            // Put away, but the terminal below it is keeping
                            // the column on screen -- so the way back has to
                            // stay reachable.
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                reopenHandle
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            // Terminal only. The empty space above it is the
                            // column holding its share of the window rather
                            // than collapsing to the height of a shell.
                            Spacer(minLength: 0)
                        }
                        if isTerminalOpen {
                            TerminalSection(root: store.rootPath, isOpen: $isTerminalOpen)
                        }
                    }
                    .frame(minWidth: 300, maxHeight: .infinity)
                }
            }
        }
        // Opening anything at all brings the column back, whether or not it
        // changed the active tab.
        .onChange(of: store.openRequests) { isCollapsed = false }
    }

    /// The way back, and the only sign the file is still open.
    ///
    /// The file tree cannot be that way: it opens on `List`'s selection
    /// changing, so clicking the row that is already selected -- exactly what
    /// someone does to bring a put-away file back -- reports nothing. A
    /// collapsed column with no handle is a file that has quietly vanished.
    private var reopenHandle: some View {
        Button {
            isCollapsed = false
        } label: {
            Image(systemName: "chevron.left.to.line")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.text(.editorExpand))
        .help(store.activeTabPath.map { ($0 as NSString).lastPathComponent } ?? Strings.text(.editorExpand))
    }
}

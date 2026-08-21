//
//  ChatSidebarView.swift
//  Puck
//
//  The workspace/session sidebar, native again (2026-08-15). Replaces
//  chat-web's Sidebar.tsx.
//
//  Stock AppKit idioms rather than a bespoke tree: `List` with a `Section`
//  per workspace is what Mail, Notes and Xcode use for exactly this shape,
//  and it brings selection, keyboard navigation, and the sidebar material
//  with it instead of asking for them to be rebuilt.
//

import SwiftUI

struct ChatSidebarView: View {
    @ObservedObject var store: ClientWindowStore
    /// Presented by the new-workspace button; the folder picker itself is
    /// AppKit's, since SwiftUI has no directory-choosing equivalent.
    @State private var isAddingWorkspace = false
    /// The chat whose Delete was picked, held until the confirmation is
    /// answered. Deleting a chat throws away everything said in it and there
    /// is no undo, so the menu item asks rather than acts.
    @State private var pendingDeletion: SessionSelection?

    var body: some View {
        List(selection: selection) {
            ForEach(store.workspaces) { workspace in
                Section {
                    ForEach(store.sessions(in: workspace.id)) { session in
                        ChatSessionRow(session: session)
                            .tag(SessionSelection(workspaceId: workspace.id, sessionId: session.id))
                            .contextMenu {
                                // Right-click on the row rather than a visible
                                // button: destructive, rarely wanted, and a
                                // trash icon on every row is a mis-click
                                // waiting to happen in a list you navigate by
                                // clicking.
                                Button(Strings.text(.commonDelete), role: .destructive) {
                                    pendingDeletion = SessionSelection(workspaceId: workspace.id, sessionId: session.id)
                                }
                                .disabled(!store.canDeleteSession(workspaceId: workspace.id, sessionId: session.id))
                            }
                    }
                } header: {
                    WorkspaceHeader(workspace: workspace)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    isAddingWorkspace = true
                } label: {
                    Label(Strings.text(.chatNewWorkspace), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            // Sits on the sidebar material rather than floating over the list,
            // so the scrolling content passes behind a real edge.
            .background(.bar)
        }
        .sheet(isPresented: $isAddingWorkspace) {
            NewWorkspaceSheet(store: store)
        }
        .confirmationDialog(
            Strings.text(.chatDeleteSessionTitle),
            isPresented: .init(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { target in
            Button(Strings.text(.commonDelete), role: .destructive) {
                store.deleteSession(workspaceId: target.workspaceId, sessionId: target.sessionId)
            }
            Button(Strings.text(.commonCancel), role: .cancel) {}
        } message: { _ in
            Text(Strings.text(.chatDeleteSessionMessage))
        }
    }

    /// Two ids as one selection value: `List` selects a single tag, and a
    /// session id alone is ambiguous -- every workspace has a session called
    /// "default" (see ClientWindowStore's composite-key note).
    private var selection: Binding<SessionSelection?> {
        Binding(
            get: { SessionSelection(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId) },
            set: { newValue in
                guard let newValue else { return }
                store.selectSession(workspaceId: newValue.workspaceId, sessionId: newValue.sessionId)
            }
        )
    }
}

struct SessionSelection: Hashable {
    let workspaceId: String
    let sessionId: String
}

private struct WorkspaceHeader: View {
    let workspace: ClientWorkspace

    // No new-chat button here. It lived in this header so it could name its
    // own workspace, but a section header styles its contents as small
    // secondary text, so it read as a stray glyph in the corner. The toolbar's
    // 새 대화 (⌘N) acts on the workspace being looked at, which is what the
    // action means nearly every time; switching first is the cost, and it is
    // smaller than a control nobody finds.
    var body: some View {
        name
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspace.name)
            if let projectPath = workspace.projectPath {
                // Same size as the name would shout twice; the path is
                // context for the name, not a second title.
                // Abbreviated with the home tilde and truncated at the head:
                // the leading /Users/<name>/ is the least informative part of
                // a project path, and the folder name is the part that
                // identifies it.
                Text((projectPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.head)
                    .lineLimit(1)
            }
        }
    }
}

private struct ChatSessionRow: View {
    @ObservedObject var session: ChatSession
    @Environment(\.clientPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            // Not pulsing: a session row sits on screen indefinitely, and a
            // dot animating for minutes reads as activity that isn't there.
            StatusDotView(status: dotStatus, palette: palette, pulses: session.isRunning)
            Text(session.displayTitle)
                .lineLimit(1)
            Spacer(minLength: 4)
            let relative = RelativeTime.short(since: session.lastActivityAt)
            if !relative.isEmpty {
                Text(relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dotStatus: DotStatus {
        if session.isRunning { return .active }
        switch session.lastRunOk {
        case .some(true): return .success
        case .some(false): return .error
        case nil: return .idle
        }
    }
}

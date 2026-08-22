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
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: ClientWindowStore
    /// The branch of the workspace being looked at, from the reader that
    /// refreshes after every write. Overrides this view's own scan for that
    /// one row: a checkout run in the window's terminal is picked up by that
    /// reader, and a sidebar still naming the old branch is worse than no
    /// branch at all.
    var activeBranch: String?
    /// Which branch each project is on, shown beside its name. Held here
    /// rather than in the store: nothing outside this list uses it, and it is
    /// read from disk rather than sent over the socket.
    @StateObject private var branches = WorkspaceBranches()
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
                    WorkspaceHeader(workspace: workspace, branch: branch(for: workspace))
                }
            }
        }
        .task(id: store.workspaces.map(\.id).joined()) {
            await branches.reload(projects: projectsByWorkspace)
        }
        .listStyle(.sidebar)
        // AppKit's own sidebar material sat two shades lighter than the
        // island beside it -- (40,39,39) against (16,16,16) -- which read as
        // two unrelated panels rather than one window. Hidden, and painted
        // with the same ground the island uses, so the two agree.
        .scrollContentBackground(.hidden)
        .background(palette.background)
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

    private func branch(for workspace: ClientWorkspace) -> String? {
        if workspace.id == store.activeWorkspaceId, let activeBranch { return activeBranch }
        return branches.branches[workspace.id]
    }

    private var projectsByWorkspace: [String: String] {
        store.workspaces.reduce(into: [:]) { result, workspace in
            result[workspace.id] = workspace.projectPath
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
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let workspace: ClientWorkspace
    /// nil when the workspace has no project, when it is not a repository, or
    /// when HEAD is detached -- none of which is a branch name.
    let branch: String?

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
        VStack(alignment: .leading, spacing: 3) {
            // Sized explicitly rather than inherited: a sidebar section
            // header styles its contents as small secondary text, so a
            // workspace's name arrived already shrunk and anything under it
            // was smaller still.
            Text(workspace.displayName)
                .font(ClientTheme.Typography.workspaceName)
                .foregroundStyle(.primary)
            if workspace.projectLabel != nil || branch != nil {
                HStack(spacing: 5) {
                    if let label = workspace.projectLabel {
                        Text(label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            // The whole path on hover, since the label is two
                            // components of it.
                            .help(workspace.projectPath ?? "")
                    }
                    if let branch {
                        // The branch belongs next to the project, not in the
                        // footer alone: the sidebar is where you pick which
                        // project to talk about, and which branch it is on is
                        // half of what that choice means.
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(branch)
                    }
                }
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .textCase(nil)
    }
}

private struct ChatSessionRow: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

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

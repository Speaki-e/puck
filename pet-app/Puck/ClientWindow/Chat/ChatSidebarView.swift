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

import AppKit
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
    /// What is typed into the filter field. Not remembered across launches:
    /// a filter left on from yesterday is a sidebar that looks empty for no
    /// visible reason.
    @State private var filter = ""

    var body: some View {
        List(selection: selection) {
            // Three groups, top to bottom: what you can start, which project
            // you are in, and the chats inside it. Taken from the reference
            // -- the old shape was one section per workspace with its chats
            // under it, which buried the project you are actually in among
            // the ones you are not.
            Section { actionRows }
            Section {
                ForEach(visibleWorkspaces) { workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        branch: branch(for: workspace),
                        isActive: workspace.id == store.activeWorkspaceId,
                        isWorking: store.sessions(in: workspace.id).contains { $0.isRunning },
                        onSelect: { select(workspace) }
                    )
                }
            } header: {
                sectionHeader(Strings.text(.chatProjects)) {
                    Button { isAddingWorkspace = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(Strings.text(.chatNewWorkspace))
                }
            }
            Section {
                ForEach(activeSessions) { session in
                    ChatSessionRow(session: session)
                        .tag(SessionSelection(workspaceId: store.activeWorkspaceId, sessionId: session.id))
                        .contextMenu {
                            // Right-click on the row rather than a visible
                            // button: destructive, rarely wanted, and a
                            // trash icon on every row is a mis-click waiting
                            // to happen in a list you navigate by clicking.
                            Button(Strings.text(.commonDelete), role: .destructive) {
                                pendingDeletion = SessionSelection(
                                    workspaceId: store.activeWorkspaceId,
                                    sessionId: session.id
                                )
                            }
                            .disabled(!store.canDeleteSession(
                                workspaceId: store.activeWorkspaceId,
                                sessionId: session.id
                            ))
                        }
                }
            } header: {
                sectionHeader(Strings.text(.chatChatsAndTasks)) { EmptyView() }
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

    /// What can be started from here, above everything that already exists.
    /// The toolbar has ⌘N too, but a sidebar whose first row is "새 대화" is
    /// how every app of this shape opens -- and the toolbar's version is a
    /// glyph you have to already know.
    @ViewBuilder
    private var actionRows: some View {
        SidebarActionRow(
            title: Strings.text(.chatNewSession),
            systemImage: "square.and.pencil"
        ) {
            store.requestNewSession(title: ChatSession.placeholderTitle, in: store.activeWorkspaceId)
        }
        SidebarActionRow(
            title: Strings.text(.chatNewWorkspace),
            systemImage: "folder.badge.plus"
        ) {
            isAddingWorkspace = true
        }
        SidebarActionRow(title: Strings.text(.chatSettings), systemImage: "gearshape") {
            NSApp.sendAction(NSSelectorFromString("showSettings:"), to: nil, from: nil)
        }
    }

    /// A group's name, with whatever acts on the group at its trailing edge.
    private func sectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            trailing()
                .foregroundStyle(palette.textSecondary)
        }
        .textCase(nil)
        .padding(.top, 4)
    }

    /// The chats of the workspace being looked at. The list used to hold
    /// every workspace's at once, one section each; a project's chats belong
    /// to the project, and the row above says which one that is.
    private var activeSessions: [ChatSession] {
        guard let workspace = store.workspaces.first(where: { $0.id == store.activeWorkspaceId }) else { return [] }
        return sessions(in: workspace)
    }

    /// Switching project keeps you in a chat: its own most recent one, or a
    /// new one if it has none.
    private func select(_ workspace: ClientWorkspace) {
        guard let session = store.sessions(in: workspace.id).first else {
            store.activeWorkspaceId = workspace.id
            return
        }
        store.selectSession(workspaceId: workspace.id, sessionId: session.id)
    }

    /// A row of its own above the list, the way Mail and Notes put it. Not
    /// `.searchable`, which on macOS moves the field into the toolbar --
    /// where it would be filtering a list it no longer sits above, and would
    /// share the bar with the chat's own controls.
    private var filterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            TextField(Strings.text(.chatFilterPlaceholder), text: $filter)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.workspaceName)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(palette.surface, in: .rect(cornerRadius: ClientTheme.Metrics.rowCornerRadius))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(palette.background)
    }

    /// Workspaces with something left to show. A workspace whose own name
    /// answers the filter keeps all of its chats; otherwise it is here only
    /// if one of its chats answers it.
    private var visibleWorkspaces: [ClientWorkspace] {
        guard SidebarFilter.isActive(filter) else { return store.workspaces }
        return store.workspaces.filter { !sessions(in: $0).isEmpty }
    }

    private func sessions(in workspace: ClientWorkspace) -> [ChatSession] {
        let all = store.sessions(in: workspace.id)
        guard SidebarFilter.isActive(filter) else { return all }
        if SidebarFilter.matchesWorkspace(filter, name: workspace.displayName, projectPath: workspace.projectPath) {
            return all
        }
        return all.filter { SidebarFilter.matchesSession(filter, title: $0.displayTitle) }
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

/// One of the things this sidebar can start. Flat, full-width and the same
/// height as every other row here, which is what makes the top of the list
/// read as a group rather than as three loose buttons.
private struct SidebarActionRow: View {
    @Environment(\.clientPalette) private var palette

    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(title)
                    .font(ClientTheme.Typography.workspaceName)
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.textPrimary)
            .frame(height: 26)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One project. Selecting it moves the whole window -- the chats below, the
/// files on the right, the branch in the footer -- so it is a row you press
/// rather than a header over a group.
private struct WorkspaceRow: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let workspace: ClientWorkspace
    /// nil when the workspace has no project, when it is not a repository, or
    /// when HEAD is detached -- none of which is a branch name.
    let branch: String?
    let isActive: Bool
    /// Whether any chat in it is mid-turn. The one thing about a project you
    /// are *not* looking at that is worth a row of its own saying.
    let isWorking: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: workspace.projectPath == nil ? "bubble.left" : "folder")
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.displayName)
                        .font(ClientTheme.Typography.workspaceName)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(ClientTheme.Typography.sessionTitle)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                        .help(Strings.text(.chatRunning))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: ClientTheme.Metrics.rowCornerRadius)
                    .fill(isActive ? palette.surface : .clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(workspace.projectPath ?? workspace.displayName)
    }

    /// The project and the branch on one line: the sidebar is where you pick
    /// which project to talk about, and which branch it is on is half of what
    /// that choice means.
    private var subtitle: String? {
        let parts = [workspace.projectLabel, branch].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            // A spinner while the turn is running, a dot once it has
            // settled, both in a box of the same size so the titles beside
            // them do not shift as runs start and finish.
            //
            // The dot pulsed instead, which is not enough to answer "is that
            // chat still working?" -- the question is being asked precisely
            // because the answer lives in a session you are not looking at.
            ZStack {
                if session.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .accessibilityLabel(Strings.text(.chatRunning))
                        .help(Strings.text(.chatRunning))
                } else {
                    StatusDotView(status: dotStatus, palette: palette, pulses: false)
                }
            }
            .frame(width: 12, height: 12)
            Text(session.displayTitle)
                .font(ClientTheme.Typography.workspaceName)
                .lineLimit(1)
            Spacer(minLength: 4)
            let relative = RelativeTime.short(since: session.lastActivityAt)
            if !relative.isEmpty {
                Text(relative)
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dotStatus: DotStatus {
        switch session.lastRunOk {
        case .some(true): return .success
        case .some(false): return .error
        case nil: return .idle
        }
    }
}

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
    /// Presented by the "새 워크스페이스" button; the folder picker itself is
    /// AppKit's, since SwiftUI has no directory-choosing equivalent.
    @State private var isAddingWorkspace = false

    var body: some View {
        List(selection: selection) {
            ForEach(store.workspaces) { workspace in
                Section {
                    ForEach(store.sessions(in: workspace.id)) { session in
                        ChatSessionRow(session: session)
                            .tag(SessionSelection(workspaceId: workspace.id, sessionId: session.id))
                    }
                } header: {
                    WorkspaceHeader(workspace: workspace) {
                        store.requestNewSession(title: ChatSession.placeholderTitle, in: workspace.id)
                    }
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
                    Label("새 워크스페이스", systemImage: "plus.circle")
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
    }

    /// Two ids as one selection value: `List` selects a single tag, and a
    /// session id alone is ambiguous -- every workspace has a session called
    /// "default" (see ClientWindowStore's composite-key note).
    private var selection: Binding<SessionSelection?> {
        Binding(
            get: { SessionSelection(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId) },
            set: { newValue in
                guard let newValue else { return }
                store.activeWorkspaceId = newValue.workspaceId
                store.activeSessionId = newValue.sessionId
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
    let onNewSession: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            name
            Spacer(minLength: 4)
            // In the header rather than one button in the bottom bar: the
            // sidebar lists every workspace at once, so a single "새 대화"
            // would have to mean "in whichever one is selected" -- and the
            // one you want a chat in is not always the one you are looking
            // at. Per header, the button names its own workspace.
            Button(action: onNewSession) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("\(workspace.name)에 새 대화")
            .accessibilityLabel("새 대화")
        }
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
            Text(session.title)
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

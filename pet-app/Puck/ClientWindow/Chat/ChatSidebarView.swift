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
    /// Which workspaces are showing their chats. Opened by clicking the
    /// workspace, and the active one opens itself -- see `body`'s task.
    @State private var expanded: Set<String> = []
    /// The full list of workspaces, as a sheet. The sidebar shows them all
    /// already when there are a few; this is for when there are not a few.
    @State private var isBrowsingWorkspaces = false

    var body: some View {
        // No `selection:`. `List` draws its own highlight for a selected row
        // -- a different shape, a different colour, and drawn edge to edge --
        // so the chats looked nothing like the projects above them, which are
        // buttons that draw their own. One list, one highlight: these draw
        // theirs too.
        List {
            // Three groups, top to bottom: what you can start, the
            // workspaces, and the chats that belong to no workspace in
            // particular. The default workspace is not a row here -- it is
            // the app's own home, and listing it beside the projects made the
            // list say "기본 워크스페이스" twice, once as a place and once as
            // the place you already were.
            Section { actionRows }
            Section {
                ForEach(visibleWorkspaces) { workspace in
                    WorkspaceGroup(
                        workspace: workspace,
                        branch: branch(for: workspace),
                        isActive: workspace.id == store.activeWorkspaceId,
                        sessions: sessions(in: workspace),
                        activeSessionId: store.activeSessionId,
                        isExpanded: Binding(
                            get: { expanded.contains(workspace.id) },
                            set: { isOpen in
                                if isOpen {
                                    expanded.insert(workspace.id)
                                } else {
                                    expanded.remove(workspace.id)
                                }
                            }
                        ),
                        onSelectSession: { session in
                            store.selectSession(workspaceId: workspace.id, sessionId: session.id)
                        },
                        onDeleteSession: { session in
                            pendingDeletion = SessionSelection(
                                workspaceId: workspace.id,
                                sessionId: session.id
                            )
                        },
                        canDeleteSession: { session in
                            store.canDeleteSession(workspaceId: workspace.id, sessionId: session.id)
                        }
                    )
                }
                .listRowInsets(Self.rowInsets)
            } header: {
                sectionHeader(Strings.text(.chatWorkspaces)) {
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
                ForEach(homeSessions) { session in
                    ChatSessionRow(
                        session: session,
                        isActive: store.activeWorkspaceId == ClientWindowStore.defaultWorkspaceId
                            && session.id == store.activeSessionId,
                        onSelect: {
                            store.selectSession(
                                workspaceId: ClientWindowStore.defaultWorkspaceId,
                                sessionId: session.id
                            )
                        }
                    )
                    .contextMenu {
                        // Right-click on the row rather than a visible
                        // button: destructive, rarely wanted, and a trash
                        // icon on every row is a mis-click waiting to happen
                        // in a list you navigate by clicking.
                        Button(Strings.text(.commonDelete), role: .destructive) {
                            pendingDeletion = SessionSelection(
                                workspaceId: ClientWindowStore.defaultWorkspaceId,
                                sessionId: session.id
                            )
                        }
                        .disabled(!store.canDeleteSession(
                            workspaceId: ClientWindowStore.defaultWorkspaceId,
                            sessionId: session.id
                        ))
                    }
                    .listRowInsets(Self.rowInsets)
                }
            } header: {
                sectionHeader(Strings.text(.chatChatsAndTasks)) { EmptyView() }
            }
        }
        // The workspace being worked in shows its chats without being asked;
        // a collapsed group holding the chat you are in is a list that hides
        // where you are.
        .onChange(of: store.activeWorkspaceId, initial: true) {
            guard store.activeWorkspaceId != ClientWindowStore.defaultWorkspaceId else { return }
            expanded.insert(store.activeWorkspaceId)
        }
        .sheet(isPresented: $isBrowsingWorkspaces) {
            WorkspaceBrowserSheet(
                store: store,
                onCreate: {
                    isBrowsingWorkspaces = false
                    isAddingWorkspace = true
                }
            )
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
        // On the row itself, not on the Section around them: a Section's
        // `listRowInsets` never reached these three, so they kept `List`'s
        // own generous gutter and sat visibly shorter than every row below.
        .listRowInsets(Self.rowInsets)
        SidebarActionRow(
            title: Strings.text(.chatWorkspaces),
            systemImage: "square.grid.2x2"
        ) {
            isBrowsingWorkspaces = true
        }
        .listRowInsets(Self.rowInsets)
        SidebarActionRow(title: Strings.text(.chatSettings), systemImage: "gearshape") {
            NSApp.sendAction(NSSelectorFromString("showSettings:"), to: nil, from: nil)
        }
        .listRowInsets(Self.rowInsets)
    }

    /// One rule for every row here. `List` leaves a generous gutter around
    /// each row by default, which is why the chats sat further from each
    /// other than they did from the heading above them -- exactly backwards,
    /// since the heading is what separates one group from the next.
    private static let rowInsets = EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0)

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
        // Air above the heading, not below it: a heading belongs to the rows
        // under it, and the gap that says "new group" goes over the top.
        .padding(.top, 12)
        .padding(.bottom, 2)
        .padding(.horizontal, 6)
    }

    /// The chats that belong to no project: the default workspace's, shown
    /// directly under "채팅 및 작업" rather than behind a row named after a
    /// place nobody chose to be in.
    private var homeSessions: [ChatSession] {
        guard let home = store.workspaces.first(where: { $0.id == ClientWindowStore.defaultWorkspaceId }) else {
            return []
        }
        return sessions(in: home)
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
        let workspaces = store.workspaces.filter { $0.id != ClientWindowStore.defaultWorkspaceId }
        guard SidebarFilter.isActive(filter) else { return workspaces }
        return workspaces.filter {
            SidebarFilter.matchesWorkspace(filter, name: $0.displayName, projectPath: $0.projectPath)
                || !sessions(in: $0).isEmpty
        }
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
}

struct SessionSelection: Hashable {
    let workspaceId: String
    let sessionId: String
}

/// Reports the pointer entering and leaving, from AppKit rather than from
/// SwiftUI's `.onHover`.
///
/// `.onHover` never fired for the rows at the top of this list. They sit
/// inside a `List`, which is an NSTableView underneath, and the row views it
/// manages do not hand plain SwiftUI content the mouse-moved events -- the
/// chats appeared to work only because a selectable row gets AppKit's own
/// hover highlight for free, and the rows with no selection tag got nothing
/// at all. A tracking area is what AppKit answers this question with, so
/// that is what this asks with.
private struct HoverReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tracking: NSTrackingArea?

        /// Never the answer to a click. This view sits behind the row's own
        /// content, and an NSView that accepts hits there would swallow every
        /// press meant for the button in front of it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            // .activeAlways rather than .activeInKeyWindow: the pointer moves
            // over this list on the way to clicking it, which is exactly the
            // moment the window is not yet key.
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}

/// The fill under a sidebar row: the selection's, the pointer's, or none.
///
/// Every row here is something you click, and until now only the selected one
/// showed it. A list that does not react to the pointer reads as a picture of
/// a list -- and with rows this close together, the highlight is also how you
/// tell which one you are about to hit.
private struct SidebarRowBackground: ViewModifier {
    @Environment(\.clientPalette) private var palette

    let isSelected: Bool
    @State private var isHovering = false

    /// Rounder than a list row's usual corner: these fills run the whole
    /// width of the column, and at that length a 4pt corner is a rectangle.
    private static let cornerRadius: CGFloat = 9

    /// How far the fill runs past the row's own box on each side. `List`
    /// keeps a margin of its own around every row that nothing can set to
    /// zero, and inside it the fill read as a small tablet under the name
    /// rather than as the row being lit. A background is allowed to overflow.
    private static let overhang: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(fill)
                    .padding(.horizontal, -Self.overhang)
            )
            // An overlay, not a background: a row that is never selected has
            // a `.clear` fill from the first frame, and a tracking view
            // nested inside that never came up -- which is why the three rows
            // at the top of this list, the only ones with no selected state,
            // never lit at all. It refuses hit tests, so the button under it
            // still takes the click.
            .overlay(HoverReporter { isHovering = $0 }.padding(.horizontal, -Self.overhang))
            .contentShape(.rect)
            // Animated, because the pointer crosses several rows on the way
            // to one and a hard flicker down the list is noise.
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// Darker than the panel it sits on rather than lighter. A pale fill on
    /// a near-black sidebar draws more attention than the name it is behind,
    /// which is backwards -- the highlight is there to say "this one", not to
    /// be the brightest thing in the column.
    private var fill: Color {
        if isSelected { return palette.surface.opacity(0.85) }
        return isHovering ? palette.surface.opacity(0.55) : .clear
    }
}

private extension View {
    func sidebarRowBackground(isSelected: Bool = false) -> some View {
        modifier(SidebarRowBackground(isSelected: isSelected))
    }
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
            .frame(height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One workspace, and the chats inside it.
///
/// Clicking it opens it rather than only switching to it: the chats that
/// belong to a workspace are the reason to go there, and they used to be
/// visible only after switching -- so choosing between two workspaces meant
/// entering one to find out what was in it.
private struct WorkspaceGroup: View {
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
    let sessions: [ChatSession]
    let activeSessionId: String
    @Binding var isExpanded: Bool
    let onSelectSession: (ChatSession) -> Void
    let onDeleteSession: (ChatSession) -> Void
    let canDeleteSession: (ChatSession) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if isExpanded {
                ForEach(sessions) { session in
                    ChatSessionRow(
                        session: session,
                        isActive: isActive && session.id == activeSessionId,
                        onSelect: { onSelectSession(session) }
                    )
                    // Indented under the workspace they belong to, which is
                    // what says they belong to it.
                    .padding(.leading, 12)
                    .contextMenu {
                        Button(Strings.text(.commonDelete), role: .destructive) {
                            onDeleteSession(session)
                        }
                        .disabled(!canDeleteSession(session))
                    }
                }
                if sessions.isEmpty {
                    Text(Strings.text(.chatNoSessionsHere))
                        .font(ClientTheme.Typography.sessionTitle)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.leading, 22)
                        .frame(height: 24, alignment: .leading)
                }
            }
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
            // Opening a workspace is also choosing it: the first chat in it
            // is what you came for, and leaving the window on another
            // workspace while its chats are on screen is the confusion this
            // list is being rebuilt to remove.
            if isExpanded, let first = sessions.first, !isActive {
                onSelectSession(first)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 12)
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
                if sessions.contains(where: { $0.isRunning }) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                        .help(Strings.text(.chatRunning))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .sidebarRowBackground(isSelected: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.displayName)
        .help(workspace.projectPath ?? workspace.displayName)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
    }

    /// The project and the branch on one line: the sidebar is where you pick
    /// which workspace to talk in, and which branch it is on is half of what
    /// that choice means.
    private var subtitle: String? {
        let parts = [workspace.projectLabel, branch].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Every workspace at once, with what each one is bound to.
///
/// The sidebar lists them too, but it lists them in a 220pt column beside
/// everything else; this is the view for choosing between more of them than
/// that column can show, and for making one.
struct WorkspaceBrowserSheet: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: ClientWindowStore
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Strings.text(.chatWorkspaces))
                    .font(ClientTheme.Typography.sectionHeader)
                Spacer()
                Button(Strings.text(.chatNewWorkspace), systemImage: "plus", action: onCreate)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
            .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.workspaces) { workspace in
                        row(workspace)
                    }
                }
                .padding(ClientTheme.Metrics.spacingMedium)
            }
            Divider()
            HStack {
                Spacer()
                Button(Strings.text(.commonClose)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ClientTheme.Metrics.spacingLarge)
        }
        .frame(width: 460, height: 420)
        .background(palette.background)
    }

    private func row(_ workspace: ClientWorkspace) -> some View {
        Button {
            if let session = store.sessions(in: workspace.id).first {
                store.selectSession(workspaceId: workspace.id, sessionId: session.id)
            } else {
                store.activeWorkspaceId = workspace.id
            }
            dismiss()
        } label: {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                Image(systemName: workspace.projectPath == nil ? "bubble.left" : "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(workspace.id == store.activeWorkspaceId ? palette.accent : palette.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.displayName)
                        .font(ClientTheme.Typography.workspaceName)
                        .foregroundStyle(palette.textPrimary)
                    Text(workspace.projectPath ?? Strings.text(.chatNoProjectLinked))
                        .font(ClientTheme.Typography.sessionTitle)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
                Text(String(store.sessions(in: workspace.id).count))
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, 6)
            .sidebarRowBackground(isSelected: workspace.id == store.activeWorkspaceId)
        }
        .buttonStyle(.plain)
    }
}

private struct ChatSessionRow: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    @Environment(\.clientPalette) private var palette

    var body: some View {
        Button(action: onSelect) {
            row
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.displayTitle)
    }

    private var row: some View {
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
        .padding(.horizontal, 6)
        .frame(height: 28)
        .sidebarRowBackground(isSelected: isActive)
    }

    private var dotStatus: DotStatus {
        switch session.lastRunOk {
        case .some(true): return .success
        case .some(false): return .error
        case nil: return .idle
        }
    }
}

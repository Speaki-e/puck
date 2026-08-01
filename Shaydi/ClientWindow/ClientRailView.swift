//
//  ClientRailView.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  2026-08-01 (byeolki: "Orbita로 해봐봐"): replaces the old resizable
//  workspace/session sidebar. Orbita GPT's own left edge is a narrow
//  icon-only rail -- a nav for a multi-feature app (chat/notifications/
//  settings/...), which Shaydi's single-purpose client doesn't need. What it
//  keeps from that structure is the *shape*: a slim icon strip, not a wide
//  text column, with anything that needs more room (the workspace list, the
//  session history) tucked behind a popover instead of permanently on
//  screen. Orbita's own remaining nav icons (notifications, integrations,
//  contacts) have no Shaydi equivalent, so this rail only holds the two
//  things the client window actually needs: which workspace, which session.
//

import SwiftUI

struct ClientRailView: View {
    @ObservedObject var store: ClientWindowStore
    @State private var showingWorkspacePopover = false
    @State private var showingHistoryPopover = false
    @State private var showingNewWorkspaceSheet = false

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingLarge) {
            // Clears the traffic-light buttons -- ClientWindow uses
            // .fullSizeContentView + a transparent titlebar so the rail's
            // own background runs to the top of the window.
            Color.clear.frame(height: 28)

            workspaceButton
            historyButton

            Spacer(minLength: 0)
        }
        .padding(.top, ClientTheme.Metrics.spacingSmall)
        .frame(width: ClientTheme.Metrics.railWidth)
        .frame(maxHeight: .infinity)
        .background(VisualEffectBackground(material: .sidebar))
        .sheet(isPresented: $showingNewWorkspaceSheet) {
            NewWorkspaceSheet(
                onCreate: { name, projectPath in
                    store.requestNewWorkspace(name: name, projectPath: projectPath)
                    showingNewWorkspaceSheet = false
                },
                onCancel: { showingNewWorkspaceSheet = false }
            )
        }
    }

    /// Orbita's own top-of-rail circle (its app/user avatar) becomes the
    /// workspace switcher here -- a single letter is enough at this size,
    /// the popover it opens carries the actual names.
    private var workspaceButton: some View {
        Button {
            showingWorkspacePopover = true
        } label: {
            Text(String((activeWorkspace?.name ?? "?").prefix(1)).uppercased())
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(ClientTheme.Colors.onAccent)
                .frame(width: ClientTheme.Metrics.railButtonSize, height: ClientTheme.Metrics.railButtonSize)
                .glassSurface(in: Circle(), tint: ClientTheme.Colors.accent)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingWorkspacePopover, arrowEdge: .trailing) {
            WorkspacePopoverContent(
                store: store,
                onSelect: { showingWorkspacePopover = false },
                onAddWorkspace: {
                    showingWorkspacePopover = false
                    showingNewWorkspaceSheet = true
                }
            )
        }
    }

    private var historyButton: some View {
        Button {
            showingHistoryPopover = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ClientTheme.Colors.secondaryText)
                .frame(width: ClientTheme.Metrics.railButtonSize, height: ClientTheme.Metrics.railButtonSize)
                .glassControl(in: Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingHistoryPopover, arrowEdge: .trailing) {
            SessionHistoryPopoverContent(store: store, onSelect: { showingHistoryPopover = false })
        }
    }
}

private struct WorkspacePopoverContent: View {
    @ObservedObject var store: ClientWindowStore
    let onSelect: () -> Void
    let onAddWorkspace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.workspaces) { workspace in
                WorkspaceRow(workspace: workspace, isActive: workspace.id == store.activeWorkspaceId) {
                    store.activeWorkspaceId = workspace.id
                    store.activeSessionId = ClientWindowStore.defaultSessionId
                    onSelect()
                }
            }
            Button(action: onAddWorkspace) {
                Label("워크스페이스 추가", systemImage: "plus")
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(ClientTheme.Colors.secondaryText)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        }
        .padding(ClientTheme.Metrics.spacingSmall)
        .frame(width: 240)
    }
}

private struct SessionHistoryPopoverContent: View {
    @ObservedObject var store: ClientWindowStore
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.sessions(in: store.activeWorkspaceId)) { session in
                SessionRow(session: session, isActive: session.id == store.activeSessionId) {
                    store.activeSessionId = session.id
                    onSelect()
                }
            }
        }
        .padding(ClientTheme.Metrics.spacingSmall)
        .frame(width: 240)
    }
}

private struct WorkspaceRow: View {
    let workspace: ClientWorkspace
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: workspace.projectPath == nil ? "bubble.left.and.bubble.right.fill" : "folder.fill")
                    .foregroundStyle(isActive ? ClientTheme.Colors.accent : ClientTheme.Colors.secondaryText)
                    .frame(width: 18)
                Text(workspace.name)
                    .font(ClientTheme.Typography.workspaceName)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(ClientTheme.Colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        .glassSurface(in: ClientTheme.Shapes.row, isEnabled: isActive)
    }
}

private struct SessionRow: View {
    @ObservedObject var session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: "message.fill")
                    .font(.caption)
                    .foregroundStyle(isActive ? ClientTheme.Colors.accent : ClientTheme.Colors.secondaryText)
                    .frame(width: 18)
                Text(session.title)
                    .font(ClientTheme.Typography.sessionTitle)
                    .lineLimit(1)
                Spacer()
                if session.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        .glassSurface(in: ClientTheme.Shapes.row, isEnabled: isActive)
    }
}

private struct NewWorkspaceSheet: View {
    let onCreate: (_ name: String, _ projectPath: String?) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var projectPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
            Text("새 워크스페이스").font(.title3.weight(.semibold))

            TextField("이름", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(projectPath ?? "프로젝트 폴더 없음 (순수 채팅)")
                    .font(.caption)
                    .foregroundStyle(ClientTheme.Colors.secondaryText)
                    .lineLimit(1)
                Spacer()
                Button("폴더 선택...") { choosePath() }
            }

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                Button("추가") { onCreate(name, projectPath) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    .glassControl(in: Capsule())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(ClientTheme.Metrics.spacingLarge * 1.5)
        .frame(width: 360)
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectPath = url.path
    }
}

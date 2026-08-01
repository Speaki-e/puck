//
//  ClientSidebarView.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  2026-08-01 design-system rebuild (byeolki: "기존 프론트엔드에서 고치기
//  보다는 프론트엔드를 처음부터 만드는 마음으로"). Replaces ClientRailView's
//  icon-only rail: the session list is real and visible here, not hidden
//  behind a popover -- reference screenshot #2 (a dark, Claude-Desktop-
//  shaped app) shows its sidebar this way, and it's a genuine usability
//  improvement over "click an icon, open a popover" for something used on
//  every message. Only the workspace switcher keeps ClientRailView's popover
//  pattern into the collapsed state, since a 56pt icon rail has no room for
//  a real list -- session switching still needs the sidebar expanded.
//

import SwiftUI

struct ClientSidebarView: View {
    @ObservedObject var store: ClientWindowStore
    @Environment(\.clientPalette) private var palette

    @State private var isExpanded = true
    @State private var showingWorkspacePopover = false
    @State private var showingThemePopover = false
    @State private var showingNewWorkspaceSheet = false

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the traffic-light buttons -- ClientWindow uses
            // .fullSizeContentView + a transparent titlebar so the sidebar's
            // own background runs to the top of the window.
            Color.clear.frame(height: 28)

            workspaceHeader
                .padding(.horizontal, isExpanded ? ClientTheme.Metrics.spacingMedium : ClientTheme.Metrics.spacingSmall)

            newChatButton
                .padding(.horizontal, isExpanded ? ClientTheme.Metrics.spacingMedium : ClientTheme.Metrics.spacingSmall)
                .padding(.top, ClientTheme.Metrics.spacingSmall)

            if isExpanded {
                sessionList
            } else {
                Spacer(minLength: 0)
            }

            footer
        }
        .frame(width: isExpanded ? ClientTheme.Metrics.sidebarWidthExpanded : ClientTheme.Metrics.sidebarWidthCollapsed)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
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

    @ViewBuilder
    private var sidebarBackground: some View {
        if palette.usesGlassSurfaces {
            VisualEffectBackground(material: .sidebar)
        } else {
            palette.background.brightness(-0.02)
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.sessions(in: store.activeWorkspaceId)) { session in
                    SidebarSessionRow(
                        session: session,
                        isActive: session.id == store.activeSessionId,
                        onSelect: { store.activeSessionId = session.id }
                    )
                }
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        }
        .padding(.top, ClientTheme.Metrics.spacingMedium)
    }

    /// The workspace switcher -- Orbita's own top-of-rail circle (its
    /// app/user avatar) becomes this. A single letter is enough when
    /// collapsed; expanded, the workspace's full name sits beside it.
    private var workspaceHeader: some View {
        Button {
            showingWorkspacePopover = true
        } label: {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Text(String((activeWorkspace?.name ?? "?").prefix(1)).uppercased())
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: ClientTheme.Metrics.railButtonSize, height: ClientTheme.Metrics.railButtonSize)
                    .background(palette.accent, in: Circle())

                if isExpanded {
                    Text(activeWorkspace?.name ?? "")
                        .font(ClientTheme.Typography.workspaceName)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
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

    private var newChatButton: some View {
        Button {
            store.requestNewSession(title: "새 채팅", in: store.activeWorkspaceId)
        } label: {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: "square.and.pencil")
                if isExpanded {
                    Text("새 채팅").font(ClientTheme.Typography.workspaceName)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            .frame(maxWidth: isExpanded ? .infinity : ClientTheme.Metrics.railButtonSize)
            .themedSurface(palette, in: ClientTheme.Shapes.row)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Divider().opacity(0.5)

            Button {
                showingThemePopover = true
            } label: {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: ClientTheme.Metrics.railButtonSize, height: ClientTheme.Metrics.railButtonSize)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingThemePopover, arrowEdge: .trailing) {
                ThemePopoverContent(selection: Binding(
                    get: { store.themeStyle },
                    set: { store.themeStyle = $0 }
                ))
            }

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: ClientTheme.Metrics.railButtonSize, height: ClientTheme.Metrics.railButtonSize)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, ClientTheme.Metrics.spacingSmall)
    }
}

private struct SidebarSessionRow: View {
    @ObservedObject var session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    @Environment(\.clientPalette) private var palette

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: "message.fill")
                    .font(.caption)
                    .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
                    .frame(width: 18)
                Text(session.title)
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(palette.textPrimary)
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
        .background(isActive ? palette.accent.opacity(0.14) : Color.clear, in: ClientTheme.Shapes.row)
    }
}

private struct WorkspacePopoverContent: View {
    @ObservedObject var store: ClientWindowStore
    let onSelect: () -> Void
    let onAddWorkspace: () -> Void
    @Environment(\.clientPalette) private var palette

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
                    .foregroundStyle(palette.textSecondary)
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

private struct WorkspaceRow: View {
    let workspace: ClientWorkspace
    let isActive: Bool
    let onSelect: () -> Void
    @Environment(\.clientPalette) private var palette

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: workspace.projectPath == nil ? "bubble.left.and.bubble.right.fill" : "folder.fill")
                    .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
                    .frame(width: 18)
                Text(workspace.name)
                    .font(ClientTheme.Typography.workspaceName)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        .background(isActive ? palette.accent.opacity(0.14) : Color.clear, in: ClientTheme.Shapes.row)
    }
}

/// The 3-way theme picker opened from the sidebar footer's palette icon.
private struct ThemePopoverContent: View {
    @Binding var selection: ClientThemeStyle
    @Environment(\.clientPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClientThemeStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    HStack {
                        Text(style.displayName)
                            .font(ClientTheme.Typography.sessionTitle)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        if style == selection {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            }
        }
        .padding(ClientTheme.Metrics.spacingSmall)
        .frame(width: 160)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("폴더 선택...") { choosePath() }
            }

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                Button("추가") { onCreate(name, projectPath) }
                    .fontWeight(.semibold)
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

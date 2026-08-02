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
//  2026-08-02: the footer's theme popover is gone -- byeolki: "테마는 셰이디
//  앱과 동기화 되어서 메뉴막대를 통한 셰이디 설정으로 변경할 수 있어야하거든".
//  ClientThemeStyle is now a Shaydi Settings item (SettingsView's "채팅
//  테마" row), synced here cross-process by ShaydiAgent's AppDelegate --
//  this view only reads store.themeStyle via clientPalette, never sets it.
//

import SwiftUI

struct ClientSidebarView: View {
    @ObservedObject var store: ClientWindowStore
    @Environment(\.clientPalette) private var palette

    @State private var isExpanded = true
    @State private var showingWorkspacePopover = false
    @State private var showingNewWorkspaceSheet = false
    @State private var isHoveringNewChat = false

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the traffic-light buttons -- ClientWindow uses
            // .fullSizeContentView + a transparent titlebar so the sidebar's
            // own background runs to the top of the window.
            Color.clear.frame(height: 28)

            header
                .padding(.horizontal, isExpanded ? ClientTheme.Metrics.spacingMedium : ClientTheme.Metrics.spacingSmall)

            newChatButton
                .padding(.horizontal, isExpanded ? ClientTheme.Metrics.spacingMedium : ClientTheme.Metrics.spacingSmall)
                .padding(.top, ClientTheme.Metrics.spacingSmall)

            if isExpanded {
                sessionList
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, ClientTheme.Metrics.spacingSmall)
        .frame(width: isExpanded ? ClientTheme.Metrics.sidebarWidthExpanded : ClientTheme.Metrics.sidebarWidthCollapsed)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        // Figma's sidebar reads as "the same white" as the main column,
        // told apart only by this hairline -- not a darker fill (byeolki,
        // 2026-08-02, "그냥 똑같이 해달라고").
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.surfaceBorder).frame(width: 1)
        }
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

    /// The workspace switcher plus the collapse toggle, together -- Figma's
    /// reference puts its own collapse/grid icon at the sidebar's top-right
    /// corner, not buried in a footer below the session list (byeolki,
    /// 2026-08-02: "그냥 똑같이 해달라고", after an earlier pass left the
    /// toggle where the pre-Figma layout had it). Side by side when
    /// expanded (room for both); stacked when collapsed (68pt has no room
    /// for the avatar and the toggle on one line).
    @ViewBuilder
    private var header: some View {
        if isExpanded {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                workspaceHeader
                Spacer(minLength: 0)
                collapseToggle
            }
        } else {
            VStack(spacing: ClientTheme.Metrics.spacingSmall) {
                workspaceHeader
                collapseToggle
            }
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

    /// byeolki, 2026-08-02: "사이드바 위주로 좀 개선해봐" -- a real, always-
    /// accurate count (`store.sessions(in:).count`) instead of a decorative
    /// label, giving the list a scannable header the way Figma's own
    /// "Today · N Total" section headers do, without inventing a date
    /// grouping this store has no timestamps to back.
    private var sessionList: some View {
        let sessions = store.sessions(in: store.activeWorkspaceId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("채팅 \(sessions.count)개")
                    .font(ClientTheme.Typography.sectionHeader)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.bottom, ClientTheme.Metrics.spacingSmall)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { session in
                        SidebarSessionRow(
                            session: session,
                            isActive: session.id == store.activeSessionId,
                            onSelect: { store.activeSessionId = session.id }
                        )
                    }
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
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // byeolki, 2026-08-02: "사이드바 하단 아이콘 버튼들에 접근성 라벨
        // 없음" -- collapsed, this is just a single letter with no other
        // text anywhere in the button; expanded, the workspace name is
        // visible but nothing states this is a *switcher*, not just a label.
        .accessibilityLabel("워크스페이스 전환")
        .accessibilityValue(activeWorkspace?.name ?? "")
        .help("워크스페이스 전환")
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
            .opacity(isHoveringNewChat ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringNewChat = $0 }
        // Collapsed, this is icon-only -- VoiceOver has nothing to read
        // without an explicit label, even though the icon itself is
        // decorative-looking (a pencil-on-paper glyph, not a real word).
        .accessibilityLabel("새 채팅")
        .help("새 채팅")
    }

    private var collapseToggle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                .foregroundStyle(palette.textSecondary)
                .frame(width: ClientTheme.Metrics.railButtonSize, height: ClientTheme.Metrics.railButtonSize)
        }
        .buttonStyle(.plain)
        // Icon-only, always -- no visible text in either state to fall
        // back on, so VoiceOver would otherwise announce nothing but
        // "button" (byeolki, 2026-08-02, from the final review's own
        // deferred finding: "사이드바 하단 아이콘 버튼들에 접근성 라벨
        // 없음").
        .accessibilityLabel(isExpanded ? "사이드바 접기" : "사이드바 펼치기")
        .help(isExpanded ? "사이드바 접기" : "사이드바 펼치기")
    }
}

private struct SidebarSessionRow: View {
    @ObservedObject var session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    @Environment(\.clientPalette) private var palette
    @State private var isHovering = false

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
        // A hover fill on top of not-active rows -- previously only the
        // active row gave any feedback at all, so every other row in the
        // list looked inert until clicked (byeolki, 2026-08-02: "사이드바
        // 위주로 좀 개선해봐").
        .background(rowBackground, in: ClientTheme.Shapes.row)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isActive { return palette.accent.opacity(0.14) }
        if isHovering { return palette.surfaceBorder.opacity(0.6) }
        return .clear
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

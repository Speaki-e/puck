//
//  ClientSidebarView.swift
//  PetAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Workspace switcher + per-workspace session list, per plan/02_pet-app.md
//  F13's sidebar layout: "위: 워크스페이스 전환 ... 아래: 새 채팅 버튼 + 지난
//  세션 목록".
//

import SwiftUI

struct ClientSidebarView: View {
    @ObservedObject var store: ClientWindowStore
    @State private var showingNewWorkspaceSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the traffic-light buttons -- ClientWindow uses
            // .fullSizeContentView + a transparent titlebar so the sidebar's
            // own background runs to the top of the window.
            Color.clear.frame(height: 28)

            // The workspace list and the session list are a split too, so a
            // long list of either can be given the room it needs
            // (byeolki: "전부 조절 가능하게").
            VSplitView {
                workspaceSection
                sessionSection
            }
        }
        // HSplitView ignores idealWidth when it lays out the first time and
        // gives a flexible child close to its max, so the max is what
        // actually decides how wide the sidebar opens -- kept near the old
        // fixed 232 rather than at a width the sidebar has no use for.
        .frame(minWidth: 180, idealWidth: ClientTheme.Metrics.sidebarWidth, maxWidth: 280)
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

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("워크스페이스")
            ScrollView {
                // One container per list: adjacent glass rows are then blended
                // by the system instead of stacking as separate slabs.
                GlassGroup(spacing: ClientTheme.Metrics.spacingSmall) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.workspaces) { workspace in
                            WorkspaceRow(workspace: workspace, isActive: workspace.id == store.activeWorkspaceId) {
                                store.activeWorkspaceId = workspace.id
                                store.activeSessionId = ClientWindowStore.defaultSessionId
                            }
                        }
                        Button {
                            showingNewWorkspaceSheet = true
                        } label: {
                            Label("워크스페이스 추가", systemImage: "plus")
                                .font(ClientTheme.Typography.sessionTitle)
                                .foregroundStyle(ClientTheme.Colors.secondaryText)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    }
                }
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            }
        }
        // Capped rather than .infinity: VSplitView splits free space evenly
        // between children that can both grow, which handed the (usually
        // one-item) workspace list half the sidebar. Still draggable inside
        // this range.
        .frame(minHeight: 90, maxHeight: 260)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.requestNewSession(title: "새 채팅", in: store.activeWorkspaceId)
            } label: {
                Label("새 채팅", systemImage: "square.and.pencil")
                    .font(ClientTheme.Typography.workspaceName)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall + 2)
                    .contentShape(Capsule())
                    .glassControl(in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)

            sectionHeader("세션")
            ScrollView {
                GlassGroup(spacing: ClientTheme.Metrics.spacingSmall) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.sessions(in: store.activeWorkspaceId)) { session in
                            SessionRow(session: session, isActive: session.id == store.activeSessionId) {
                                store.activeSessionId = session.id
                            }
                        }
                    }
                }
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 140, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(ClientTheme.Typography.sectionHeader)
            .foregroundStyle(ClientTheme.Colors.secondaryText)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.top, ClientTheme.Metrics.spacingMedium)
            .padding(.bottom, ClientTheme.Metrics.spacingSmall)
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
                    .foregroundStyle(isActive ? Color.primary : ClientTheme.Colors.secondaryText)
                    .frame(width: 18)
                Text(workspace.name)
                    .font(ClientTheme.Typography.workspaceName)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(ClientTheme.Colors.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        // Selection is a raised glass surface now, not an accent-tinted fill.
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
                    .foregroundStyle(isActive ? Color.primary : ClientTheme.Colors.secondaryText)
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
        // Selection is a raised glass surface now, not an accent-tinted fill.
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


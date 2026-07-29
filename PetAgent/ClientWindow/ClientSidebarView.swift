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
            sectionHeader("워크스페이스")
            ScrollView {
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
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                }
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            }
            .frame(maxHeight: 160)

            Divider()

            Button {
                store.requestNewSession(title: "새 채팅", in: store.activeWorkspaceId)
            } label: {
                Label("새 채팅", systemImage: "square.and.pencil")
                    .font(ClientTheme.Typography.workspaceName)
                    .foregroundStyle(ClientTheme.Colors.accent)
            }
            .buttonStyle(.plain)
            .padding(ClientTheme.Metrics.spacingMedium)

            sectionHeader("세션")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.sessions(in: store.activeWorkspaceId)) { session in
                        SessionRow(session: session, isActive: session.id == store.activeSessionId) {
                            store.activeSessionId = session.id
                        }
                    }
                }
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            }

            Spacer()
        }
        .frame(width: ClientTheme.Metrics.sidebarWidth)
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
        .background(isActive ? ClientTheme.Colors.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.rowCornerRadius, style: .continuous))
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
        .background(isActive ? ClientTheme.Colors.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.rowCornerRadius, style: .continuous))
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
                    .buttonStyle(.borderedProminent)
                    .tint(ClientTheme.Colors.accent)
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

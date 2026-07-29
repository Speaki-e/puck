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
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxHeight: 160)

            Divider()

            Button {
                store.requestNewSession(title: "새 채팅", in: store.activeWorkspaceId)
            } label: {
                Label("새 채팅", systemImage: "plus.bubble")
            }
            .buttonStyle(.plain)
            .padding(8)

            sectionHeader("세션")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.sessions(in: store.activeWorkspaceId)) { session in
                        SessionRow(session: session, isActive: session.id == store.activeSessionId) {
                            store.activeSessionId = session.id
                        }
                    }
                }
            }

            Spacer()
        }
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
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }
}

private struct WorkspaceRow: View {
    let workspace: ClientWorkspace
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(workspace.name)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
}

private struct SessionRow: View {
    @ObservedObject var session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(session.title).lineLimit(1)
                Spacer()
                if session.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
}

private struct NewWorkspaceSheet: View {
    let onCreate: (_ name: String, _ projectPath: String?) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var projectPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("새 워크스페이스").font(.headline)
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
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

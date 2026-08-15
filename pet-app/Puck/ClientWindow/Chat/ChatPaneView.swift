//
//  ChatPaneView.swift
//  Puck
//
//  The chat window's whole UI, native again (2026-08-15) -- replaces
//  ClientChatWebView and the chat-web bundle behind it. See
//  docs/superpowers/specs/2026-08-15-native-chat-design.md.
//
//  Reads ClientWindowStore/ChatSession directly. Those were always the source
//  of truth; chat-web was a second consumer of them over a hand-mirrored JSON
//  bridge, and removing it removes the mirror rather than any state.
//

import SwiftUI

struct ChatPaneView: View {
    @ObservedObject var store: ClientWindowStore
    /// Whether the editor pane is showing, owned by ClientWindowView -- the
    /// toggle lives in this view's toolbar but the split is its parent's.
    @Binding var isEditorOpen: Bool

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store)
                // Allowed to compress to 180: at the 960pt window minimum the
                // three panes (sidebar, chat, editor) are already tight, and a
                // sidebar that refuses to give any width back is what squeezed
                // the composer's placeholder onto two lines. A capped maximum
                // stops it eating the chat when the window is wide instead.
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = activeSession {
            VStack(spacing: 0) {
                ChatTranscriptView(session: session) { approved in
                    store.respondToPendingApproval(in: session, approved: approved)
                }
                Divider()
                ChatInputBar(
                    isRunning: session.isRunning,
                    onSend: { text in store.sendMessage(text, source: .text) },
                    onCancel: { store.cancelActiveRun() }
                )
            }
            .navigationTitle(session.title)
            .navigationSubtitle(activeWorkspace?.name ?? "")
            .toolbar { toolbarContent }
        } else {
            // Only reachable if the active ids point at a session that no
            // longer exists; the store always seeds one per workspace.
            ContentUnavailableView("대화를 선택하세요", systemImage: "bubble.left.and.bubble.right")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                isEditorOpen.toggle()
            } label: {
                Label("에디터", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .disabled(activeWorkspace?.canOpenEditor != true)
            .help(activeWorkspace?.canOpenEditor == true
                  ? "에디터"
                  : "이 워크스페이스에는 연결된 프로젝트가 없어요")
            // A keyboard shortcut, which the web toggle never had: the button
            // was the only way in, so the pane could not be opened without a
            // mouse (and could not be driven by automation at all).
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        ToolbarItem {
            Button {
                NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
            } label: {
                Label("설정", systemImage: "gearshape")
            }
        }
    }

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private var activeSession: ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }
}

/// The composer. `TextField(axis: .vertical)` grows with its content and
/// keeps the stock focus ring and text behaviours, which a custom NSTextView
/// wrapper would have to reproduce.
struct ChatInputBar: View {
    let isRunning: Bool
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Agent에게 메시지를 보내세요…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isFocused)
                .onSubmit(send)

            if isRunning {
                Button(role: .cancel, action: onCancel) {
                    Label("중지", systemImage: "stop.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .help("중지")
            } else {
                Button(action: send) {
                    Label("보내기", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(trimmed.isEmpty)
                .help("보내기")
            }
        }
        .padding(12)
        .buttonStyle(.plain)
        .font(.title3)
        .onAppear { isFocused = true }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}

/// "새 워크스페이스". The folder itself is chosen with NSOpenPanel -- SwiftUI
/// has no directory picker, and the panel is what the web version reached
/// through the bridge to get anyway.
struct NewWorkspaceSheet: View {
    @ObservedObject var store: ClientWindowStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var projectPath: String?

    var body: some View {
        Form {
            TextField("이름", text: $name)
            LabeledContent("프로젝트 폴더") {
                HStack {
                    Text(projectPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "선택 안 함")
                        .foregroundStyle(projectPath == nil ? .secondary : .primary)
                        .truncationMode(.head)
                        .lineLimit(1)
                    Button("선택…", action: chooseFolder)
                }
            }
            Text("폴더를 연결하면 에디터와 코드 편집을 쓸 수 있어요. 대화만 할 거면 비워 두세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                Button("만들기") {
                    store.requestNewWorkspace(name: name, projectPath: projectPath)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectPath = url.path
        // Naming a workspace after its folder is what the user would type
        // anyway; still editable above.
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.lastPathComponent
        }
    }
}

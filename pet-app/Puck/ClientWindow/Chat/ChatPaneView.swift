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
    /// Where the editor is showing, owned by ClientWindowView -- the toggle
    /// lives in this view's toolbar but the split is its parent's.
    @Binding var editor: EditorPresentation

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
                editor = editor.toggled
            } label: {
                Label("에디터", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .disabled(activeWorkspace?.canOpenEditor != true || editor == .detached)
            .help(editorButtonHelp)
            // A keyboard shortcut, which the web toggle never had: the button
            // was the only way in, so the pane could not be opened without a
            // mouse (and could not be driven by automation at all).
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        ToolbarItem {
            Button {
                editor = editor == .detached ? .attached : .detached
            } label: {
                Label(
                    editor == .detached ? "에디터 붙이기" : "에디터 떼기",
                    systemImage: editor == .detached
                        ? "arrow.down.right.and.arrow.up.left"
                        : "macwindow.on.rectangle"
                )
            }
            .disabled(activeWorkspace?.canOpenEditor != true)
            .help(editor == .detached ? "에디터를 이 창으로 다시 붙여요" : "에디터를 별도 창으로 떼어내요")
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        ToolbarItem {
            Button {
                NSApp.sendAction(NSSelectorFromString("showSettings:"), to: nil, from: nil)
            } label: {
                Label("설정", systemImage: "gearshape")
            }
        }
    }

    private var editorButtonHelp: String {
        guard activeWorkspace?.canOpenEditor == true else { return "이 워크스페이스에는 연결된 프로젝트가 없어요" }
        return editor == .detached ? "에디터가 별도 창에 열려 있어요" : "에디터"
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

    /// One number for both controls, rather than two intrinsic heights that
    /// happen to be close: the field's collapsed height is `minHeight` and the
    /// button is a square of the same size, so they cannot drift apart. 32 is
    /// the field's own single-line height at `.title3` (an 18pt line plus the
    /// 7pt padding twice) and the standard macOS control height.
    ///
    /// The field grows to eight lines; the button deliberately keeps this
    /// height and stays bottom-aligned instead of stretching. A stop/send
    /// glyph centred in a 200pt-tall column would drift away from the caret
    /// and from where it sat a moment earlier, and the button is a control the
    /// pointer aims at, not a panel -- the pair only has to read as aligned at
    /// the edge the user is typing on.
    static let controlHeight: CGFloat = 32

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Agent에게 메시지를 보내세요…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isFocused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: Self.controlHeight)
                // A field the pointer can find. Bare text on the window looked
                // like a label until you happened to click it.
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: 1)
                )

            if isRunning {
                Button(role: .cancel, action: onCancel) {
                    Label("중지", systemImage: "stop.circle.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: Self.controlHeight, height: Self.controlHeight)
                        // The whole square is the target, not just the glyph --
                        // .plain hit-tests the label's own bounds otherwise.
                        .contentShape(.rect)
                }
                .help("중지")
            } else {
                Button(action: send) {
                    Label("보내기", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: Self.controlHeight, height: Self.controlHeight)
                        .contentShape(.rect)
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

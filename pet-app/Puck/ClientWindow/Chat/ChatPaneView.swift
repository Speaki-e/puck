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
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

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
                PetTankView { store.setTankSegment($0, for: .chat) }
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
            .navigationTitle(session.displayTitle)
            .navigationSubtitle(activeWorkspace?.displayName ?? "")
            .toolbar { toolbarContent }
        } else {
            // Only reachable if the active ids point at a session that no
            // longer exists; the store always seeds one per workspace.
            ContentUnavailableView(Strings.text(.chatSelectAConversation), systemImage: "bubble.left.and.bubble.right")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading, and the first thing in the window's toolbar: the only other
        // way to start a chat is the icon in a sidebar section header, which
        // is per-workspace and therefore small and easy to miss. This one acts
        // on the workspace already being looked at, which is what "새 대화"
        // means nearly every time, and ⌘N is where every Mac app puts it.
        ToolbarItem(placement: .navigation) {
            Button {
                store.requestNewSession(title: ChatSession.placeholderTitle, in: store.activeWorkspaceId)
            } label: {
                Label(Strings.text(.chatNewSession), systemImage: "square.and.pencil")
            }
            .help(newSessionHelp)
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem {
            Button {
                editor = editor.toggled
            } label: {
                Label(Strings.text(.chatEditor), systemImage: "chevron.left.forwardslash.chevron.right")
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
                    Strings.text(editor == .detached ? .chatAttachEditor : .chatDetachEditor),
                    systemImage: editor == .detached
                        ? "arrow.down.right.and.arrow.up.left"
                        : "macwindow.on.rectangle"
                )
            }
            .disabled(activeWorkspace?.canOpenEditor != true)
            .help(Strings.text(editor == .detached ? .chatAttachEditorHelp : .chatDetachEditorHelp))
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        ToolbarItem {
            Button {
                NSApp.sendAction(NSSelectorFromString("showSettings:"), to: nil, from: nil)
            } label: {
                Label(Strings.text(.chatSettings), systemImage: "gearshape")
            }
        }
    }

    /// Names the workspace the chat would be created in -- "this workspace"
    /// only when it has no name to give.
    private var newSessionHelp: String {
        let workspace = activeWorkspace?.displayName ?? Strings.text(.chatThisWorkspace)
        return "\(workspace) · \(Strings.text(.chatNewSession))"
    }

    private var editorButtonHelp: String {
        guard activeWorkspace?.canOpenEditor == true else { return Strings.text(.chatNoProjectLinked) }
        return Strings.text(editor == .detached ? .chatEditorInSeparateWindow : .chatEditor)
    }

    private var activeWorkspace: ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private var activeSession: ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }
}

/// A composer button's icon, drawn at the control height instead of at the
/// surrounding font's icon size. `Label` sizes a glyph from the font, which
/// left a 15pt circle beside a 32pt field -- the hit target matched, but the
/// button read as half the field's size.
private struct ControlGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: ChatInputBar.controlHeight, height: ChatInputBar.controlHeight)
            // The whole square is the target, not just the glyph -- .plain
            // hit-tests the image's own bounds otherwise.
            .contentShape(.rect)
    }
}

/// The composer. `TextField(axis: .vertical)` grows with its content and
/// keeps the stock focus ring and text behaviours, which a custom NSTextView
/// wrapper would have to reproduce.
struct ChatInputBar: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

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
            TextField(Strings.text(.chatComposerPlaceholder), text: $text, axis: .vertical)
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
                    ControlGlyph(systemName: "stop.circle.fill")
                }
                .accessibilityLabel(Strings.text(.chatStop))
                .help(Strings.text(.chatStop))
            } else {
                Button(action: send) {
                    ControlGlyph(systemName: "arrow.up.circle.fill")
                }
                .disabled(trimmed.isEmpty)
                .accessibilityLabel(Strings.text(.chatSend))
                .help(Strings.text(.chatSend))
            }
        }
        .frame(maxWidth: ClientTheme.Metrics.transcriptColumnWidth)
        .padding(.horizontal, ClientTheme.Metrics.transcriptHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
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

/// The new-workspace sheet. The folder itself is chosen with NSOpenPanel -- SwiftUI
/// has no directory picker, and the panel is what the web version reached
/// through the bridge to get anyway.
struct NewWorkspaceSheet: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var store: ClientWindowStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var projectPath: String?

    var body: some View {
        Form {
            TextField(Strings.text(.chatWorkspaceName), text: $name)
            LabeledContent(Strings.text(.chatProjectFolder)) {
                HStack {
                    Text(projectPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? Strings.text(.chatNoFolderSelected))
                        .foregroundStyle(projectPath == nil ? .secondary : .primary)
                        .truncationMode(.head)
                        .lineLimit(1)
                    Button(Strings.text(.commonChoose), action: chooseFolder)
                }
            }
            Text(Strings.text(.chatProjectFolderExplanation))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(Strings.text(.commonCancel), role: .cancel) { dismiss() }
                Button(Strings.text(.commonCreate)) {
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

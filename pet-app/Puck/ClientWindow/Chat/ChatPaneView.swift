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

import AppKit
import SwiftUI

struct ChatPaneView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: ClientWindowStore
    /// Where the editor is showing, owned by ClientWindowView -- the toggle
    /// lives in this view's toolbar but the split is its parent's.
    @Binding var editor: EditorPresentation
    /// The project's files, when this workspace has one. Held by
    /// ClientWindowView; this view only splits its detail around it.
    var editorStore: EditorPaneStore?
    /// The active project's branch, passed through to the sidebar -- see
    /// ChatSidebarView.activeBranch.
    var activeBranch: String?
    /// Which of the right column's three lists is showing, when that column
    /// is on screen. In the toolbar because the band above it was empty --
    /// the whole width of it, over the one column with no chrome of its own.
    var explorerTab: Binding<ExplorerTab>?

    /// Where the toolbar's last button ends, measured rather than assumed --
    /// the island climbs into the empty band past it, and a hard-coded x
    /// would be wrong the first time a button was added. Nil until the
    /// toolbar has laid itself out.
    @State private var toolbarTrailingX: CGFloat?
    /// The same key CodeSplitView stores it under. The toggle is in the
    /// window's toolbar as well as in the code column's own strip, because
    /// the column is what it opens: a shortcut that only exists once the
    /// column is showing cannot be the way you show it -- with the column
    /// closed the key press fell through to the composer as a stray backtick.
    @AppStorage(TerminalSection.openStorageKey) private var isTerminalOpen = false

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store, activeBranch: activeBranch)
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
            // Above `conversation`, not inside the chat column: the tank is a
            // strip across the whole detail area, and it was one before the
            // code column existed. Putting it inside would shrink the pet's
            // home to the chat's width the moment a file is opened.
            VStack(spacing: 0) {
                PetTankView(
                    onFrameChange: { store.setTankSegment($0, for: .chat) },
                    onPetHeightChange: { store.setPetIslandHeight($0) },
                    toolbarTrailingX: toolbarTrailingX
                )
                conversation(session)
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

    /// The conversation, and beside it the file that was opened from the
    /// explorer. Split rather than swapped: the reason to look at a file is
    /// usually what was just said about it, and a layout that shows one by
    /// hiding the other makes you choose between them.
    @ViewBuilder
    private func conversation(_ session: ChatSession) -> some View {
        if let editorStore {
            // Through a view that observes the store rather than deciding
            // here: whether a file is open is one of its published
            // properties, and a plain `var` is not an input SwiftUI watches.
            // Read straight from this body, clicking a file in the explorer
            // highlighted the row and split nothing.
            ConversationSplit(store: editorStore) { chatColumn(session) }
        } else {
            chatColumn(session)
        }
    }

    private func chatColumn(_ session: ChatSession) -> some View {
        // No ground of its own: the window's backdrop is the ground, and a
        // column painting over it would be the one opaque rectangle in a
        // translucent window.
        chatStack(session)
    }

    private func chatStack(_ session: ChatSession) -> some View {
        VStack(spacing: 0) {
            ChatTranscriptView(session: session) { approved in
                store.respondToPendingApproval(in: session, approved: approved)
            }
            // No rule above the composer: the box already has an edge of its
            // own, and a full-width line over it cut the window in two.
            ChatInputBar(
                isRunning: session.isRunning,
                onSend: { text, attachments in
                    store.sendMessage(text, source: .text, attachments: attachments.isEmpty ? nil : attachments)
                },
                onCancel: { store.cancelActiveRun() },
                onVoiceListening: { store.setVoiceListening($0) }
            )
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
                guard activeWorkspace?.canOpenEditor == true else { return }
                isTerminalOpen.toggle()
                if isTerminalOpen, editor == .hidden { editor = .attached }
            } label: {
                Label(Strings.text(.terminalToggle), systemImage: "terminal")
            }
            .disabled(activeWorkspace?.canOpenEditor != true)
            .keyboardShortcut("`", modifiers: .control)
            .help(Strings.text(.terminalToggle))
        }
        if let explorerTab {
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: explorerTab) {
                    ForEach(ExplorerTab.allCases) { tab in
                        Image(systemName: tab.symbolName)
                            .help(tab.displayName)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Rebuilt on a language change: NSSegmentedControl keeps the
                // titles it was built with, so its accessibility labels would
                // stay in the old language.
                .id(localization.language)
                .help(Strings.text(.explorerTabFiles))
            }
        }
        ToolbarItem {
            Button {
                NSApp.sendAction(NSSelectorFromString("showSettings:"), to: nil, from: nil)
            } label: {
                Label(Strings.text(.chatSettings), systemImage: "gearshape")
            }
            // The last button in the group, so its trailing edge is where the
            // toolbar ends and the island's shoulder may begin.
            .background(GlobalFrameReporter { toolbarTrailingX = $0.maxX })
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

/// The conversation, and beside it the file the explorer opened.
///
/// Split rather than swapped: the reason to look at a file is usually what
/// was just said about it, and a layout that shows one by hiding the other
/// makes you choose between them.
private struct ConversationSplit<Chat: View>: View {
    @ObservedObject var store: EditorPaneStore
    @ViewBuilder var chat: Chat

    /// The shell under the code. Read here rather than only inside
    /// CodeSplitView because it has to be reachable with no file open: the
    /// terminal used to live inside the code column, so asking for one before
    /// opening a file toggled a setting and showed nothing.
    @AppStorage(TerminalSection.openStorageKey) private var isTerminalOpen = false

    /// Put away rather than closed. The tab stays open, so coming back to the
    /// file does not mean finding it again -- and opening another one from
    /// the explorer brings the column back, which is what the click means.
    @State private var isCollapsed = false

    var body: some View {
        Group {
            if store.activeTabPath == nil, !isTerminalOpen {
                chat
            } else if store.activeTabPath != nil, isCollapsed, !isTerminalOpen {
                HStack(spacing: 0) {
                    chat
                    Divider()
                    reopenHandle
                }
            } else {
                HSplitView {
                    chat.frame(minWidth: 320)
                    VStack(spacing: 0) {
                        if store.activeTabPath != nil, !isCollapsed {
                            CodeSplitView(store: store) { isCollapsed = true }
                                .frame(maxHeight: .infinity)
                        } else if store.activeTabPath != nil {
                            // Put away, but the terminal below it is keeping
                            // the column on screen -- so the way back has to
                            // stay reachable.
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                reopenHandle
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            // Terminal only. The empty space above it is the
                            // column holding its share of the window rather
                            // than collapsing to the height of a shell.
                            Spacer(minLength: 0)
                        }
                        if isTerminalOpen {
                            TerminalSection(root: store.rootPath, isOpen: $isTerminalOpen)
                        }
                    }
                    .frame(minWidth: 300, maxHeight: .infinity)
                }
            }
        }
        // Opening anything at all brings the column back, whether or not it
        // changed the active tab.
        .onChange(of: store.openRequests) { isCollapsed = false }
    }

    /// The way back, and the only sign the file is still open.
    ///
    /// The file tree cannot be that way: it opens on `List`'s selection
    /// changing, so clicking the row that is already selected -- exactly what
    /// someone does to bring a put-away file back -- reports nothing. A
    /// collapsed column with no handle is a file that has quietly vanished.
    private var reopenHandle: some View {
        Button {
            isCollapsed = false
        } label: {
            Image(systemName: "chevron.left.to.line")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.text(.editorExpand))
        .help(store.activeTabPath.map { ($0 as NSString).lastPathComponent } ?? Strings.text(.editorExpand))
    }
}

/// The composer: one box holding the message and everything sent with it.
///
/// It used to be a field with a round arrow button floating beside it, and
/// the settings that shape a turn -- how much thinking, which model -- lived
/// only behind slash commands nobody discovers. They are on the box now, in
/// the corners where every chat app of this kind puts them: what to attach on
/// the left, what to answer with on the right.
///
/// `TextField(axis: .vertical)` grows with its content and keeps the stock
/// focus ring and text behaviours, which a custom NSTextView wrapper would
/// have to reproduce.
struct ChatInputBar: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let isRunning: Bool
    let onSend: (String, [Attachment]) -> Void
    let onCancel: () -> Void
    /// Asks pet-app to hold its push-to-talk down or let it up. The chat
    /// window has no microphone; see BridgeMessage.voiceListen.
    var onVoiceListening: ((Bool) -> Void)?

    @State private var text = ""
    @State private var attachments: [Attachment] = []
    /// Whether pet-app is holding its push-to-talk down for us. A hold, not a
    /// press: speech is finalised on release, so the button stays lit until
    /// it is clicked again.
    @State private var isListening = false
    /// Read once and after every change rather than on each render: both come
    /// off disk (a `.env` and the environment), and `body` runs on every
    /// keystroke.
    @State private var effort = AgentConfiguration.effort()
    @State private var configuration = AgentConfiguration.load()
    /// How much the agent may do on its own this turn. The setting that
    /// changes most often and matters most per message, which is why it is
    /// what the control says rather than which CLI is answering.
    @State private var permissions = AgentConfiguration.permissionMode()
    @FocusState private var isFocused: Bool

    /// The height of the controls along the bottom of the box, and of the
    /// stop button. Everything here is a hit target at arm's length rather
    /// than a glyph to squint at.
    static let controlHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Above the field, not below it: the field is already at the
            // bottom of the window, and a list under it would open off
            // screen.
            if !suggestions.isEmpty {
                SlashSuggestionList(suggestions: suggestions) { suggestion in
                    text = suggestion.completion
                    isFocused = true
                }
            }
            composer
        }
        .frame(maxWidth: ClientTheme.Metrics.transcriptColumnWidth)
        .padding(.horizontal, ClientTheme.Metrics.transcriptHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .onAppear { isFocused = true }
    }

    /// Offered while a command is being typed, and only then -- see
    /// SlashCommand.suggestions.
    private var suggestions: [SlashSuggestion] {
        SlashCommand.suggestions(for: text)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.isEmpty { attachmentRow }
            TextField(Strings.text(.chatComposerPlaceholder), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.transcriptBody)
                // Three lines' worth of room before anything is typed, so the
                // box has the presence the reference's does rather than
                // growing into it.
                .lineLimit(3...12)
                .focused($isFocused)
                // Return sends. There is no button to press instead, which is
                // the point: the arrow was a control the eye had to find for
                // something the hand was already doing.
                .onSubmit(send)
            controlRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
        // Rounder and quieter than the old box: the reference's composer is a
        // soft-edged well the controls sit inside, not a bordered field with
        // a button beside it.
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(isFocused ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.separator), lineWidth: 1)
        )
    }

    /// What is going with the message, above the text it belongs to.
    private var attachmentRow: some View {
        HStack(spacing: 4) {
            ForEach(attachments, id: \.path) { attachment in
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                    Text((attachment.path as NSString).lastPathComponent)
                        .font(ClientTheme.Typography.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        attachments.removeAll { $0.path == attachment.path }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(palette.surface, in: .rect(cornerRadius: ClientTheme.Metrics.rowCornerRadius))
            }
            Spacer(minLength: 0)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 6) {
            attachButton
            Spacer(minLength: 0)
            // Model and effort as one control, the way the reference has it:
            // they are one question -- what should answer this -- and two
            // adjacent menus of two words each read as clutter.
            settingsMenu
            micButton
            if isRunning { stopButton }
        }
        .font(ClientTheme.Typography.sessionTitle)
        .foregroundStyle(palette.textSecondary)
    }

    /// "파일 수정까지 · 보통 ∨" -- the mode the agent is running under and how
    /// much thinking it is doing, which are the two answers to "what happens
    /// when I press return". Which CLI is behind it changes once a month and
    /// lives in Settings; the mode changes several times an hour.
    private var settingsMenu: some View {
        Menu {
            Section(Strings.text(.permissionsLabel)) {
                ForEach(AgentPermissionMode.allCases) { mode in
                    Button(mode.displayName) { run("/permissions \(mode.rawValue)") }
                }
            }
            Section(Strings.text(.chatEffort)) {
                ForEach(AgentEffort.allCases) { level in
                    Button(level.displayName) { run("/effort \(level.rawValue)") }
                }
            }
            if configuration.provider.supportsModelSelection {
                Section(Strings.text(.chatModel)) {
                    ForEach(
                        AgentProvider.selectableModels(for: configuration.provider, configured: configuration.model),
                        id: \.self
                    ) { model in
                        Button(model) { run("/model \(model)") }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(modeLabel)
                    .foregroundStyle(palette.textPrimary)
                Text(effort.displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: Self.controlHeight)
            .contentShape(.rect)
        }
        // `.borderlessButton` throws the label away: it renders as an
        // NSPopUpButton, which takes a title and nothing else, so the two
        // words and the chevron here came out as one word with the system's
        // own arrow on the wrong side. `.button` draws what it was given.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The permission mode, or the model where the model is the thing being
    /// chosen -- an API provider has no CLI to permit anything to.
    private var modeLabel: String {
        configuration.provider == .cli ? permissions.displayName : configuration.model
    }

    /// pet-app does the listening. Lit while it is, and drawn as a waveform
    /// then -- the same two glyphs the reference shows, one state each.
    private var micButton: some View {
        Button {
            isListening.toggle()
            onVoiceListening?(isListening)
        } label: {
            Image(systemName: isListening ? "waveform" : "mic")
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(.rect)
        }
        .foregroundStyle(isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.textSecondary))
        .disabled(onVoiceListening == nil)
        .accessibilityLabel(Strings.text(.chatVoice))
        .help(Strings.text(.chatVoice))
    }

    /// Images only: an attachment travels as `type: "image"` on the wire, and
    /// offering a picker that accepts anything would promise more than the
    /// protocol carries.
    private var attachButton: some View {
        Button(action: chooseAttachment) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(.rect)
        }
        .accessibilityLabel(Strings.text(.chatAttach))
        .help(Strings.text(.chatAttach))
    }

    private var stopButton: some View {
        Button(role: .cancel, action: onCancel) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background(palette.surface, in: .rect(cornerRadius: ClientTheme.Metrics.rowCornerRadius))
                .contentShape(.rect)
        }
        .accessibilityLabel(Strings.text(.chatStop))
        .help(Strings.text(.chatStop))
    }

    /// Sends a slash command as if it had been typed, then re-reads what it
    /// wrote -- the runner reports the value it read back, and so does this.
    private func run(_ command: String) {
        onSend(command, [])
        effort = AgentConfiguration.effort()
        configuration = AgentConfiguration.load()
        permissions = AgentConfiguration.permissionMode()
    }

    private func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.map { Attachment(path: $0.path) }
        // No duplicates: picking the same file twice sends it twice.
        attachments += chosen.filter { candidate in !attachments.contains { $0.path == candidate.path } }
        isFocused = true
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        // An attachment on its own is a message: "look at this" with the
        // picture doing the talking.
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        onSend(trimmed, attachments)
        text = ""
        attachments = []
    }
}

/// What can be typed next, while a command is being typed.
///
/// A plain list rather than a popover: the commands are few, the field is
/// right below it, and a popover over a window that is mostly conversation
/// hides the thing being talked about.
private struct SlashSuggestionList: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let suggestions: [SlashSuggestion]
    let onPick: (SlashSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Text("/\(suggestion.name)")
                            .font(ClientTheme.Typography.mono)
                            .foregroundStyle(palette.textPrimary)
                        Text(suggestion.summary)
                            .font(ClientTheme.Typography.sessionTitle)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: ClientTheme.Metrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius)
                .strokeBorder(palette.surfaceBorder, lineWidth: 1)
        }
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

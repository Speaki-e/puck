//
//  ClientWindowStore.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Source of truth for the client window's sidebar: workspaces, each
//  workspace's chat sessions, and which one is active. Wired to
//  BridgeMessageRouter.onClientUpdate/onChatEvent for incoming state and
//  UserInputSender for outgoing requests (plan/02_pet-app.md F13).
//

import Foundation

final class ClientWindowStore: ObservableObject {
    static let defaultWorkspaceId = "default"
    static let defaultSessionId = "default"
    /// 02_pet-app.md F13 calls the always-present default session/workspace
    /// the "일상 대화" (casual conversation) one -- this was the English word
    /// "Casual" until 2026-08-02, which leaked into the sidebar/topBar UI
    /// despite the rest of the app being Korean-only.
    private static let casualSessionTitle = "일상 대화"

    /// Sessions are keyed on (workspaceId, sessionId), not sessionId alone:
    /// every workspace gets its own "default" casual session (see
    /// seedDefaultSession), so session_id is only unique within a workspace.
    private struct SessionKey: Hashable {
        let workspaceId: String
        let sessionId: String
    }

    private let sender: UserInputSender
    private var sessionsByKey: [SessionKey: ChatSession] = [:]
    private var sessionOrder: [SessionKey] = []

    /// F15 (2026-07-31): set when an agent runs in this process, which it now
    /// does -- see AgentHost. A command then goes straight to it instead of
    /// out as user_input, since user_input exists to hand the command to
    /// *workspace's* agent and there is no workspace. Left nil in tests and
    /// wherever no agent is attached, in which case the old socket path
    /// stands.
    var onUserCommand: ((_ text: String, _ workspaceId: String, _ sessionId: String) -> Void)?
    /// Same reason: approval is resolved inside this process, not by a
    /// workspace on the far side of the socket.
    var onApprovalResolved: ((_ approvalId: String, _ approved: Bool) -> Void)?
    var onRunCancelled: (() -> Void)?

    @Published private(set) var workspaces: [ClientWorkspace]
    @Published var activeWorkspaceId: String
    @Published var activeSessionId: String

    /// The theme should stay in sync with the menu bar settings, the same
    /// way Shady-style apps let you flip theme from the menu bar -- so it's
    /// a Puck Settings item now
    /// (SettingsStore.clientThemeStyle), not a ClientWindow-local one. This
    /// store doesn't persist or own the value at all; PuckClient's
    /// AppDelegate seeds it at launch (reading Puck's UserDefaults domain)
    /// and keeps it live via a DistributedNotificationCenter broadcast --
    /// same shape the old `appearance` property (removed 2026-08-01, since
    /// undone here) used for Puck's own system-wide AppAppearance.
    @Published var themeStyle: ClientThemeStyle = .dark

    /// Bumped when the agent wants a file on screen -- ClientWindowView opens
    /// the editor pane in response. A counter rather than a Bool: two files in
    /// a row have to register as two requests, and the second one must still
    /// re-open a pane the user closed in between.
    @Published private(set) var editorRevealRequests = 0

    /// Called when the agent opens a file for the user to look at, or edits
    /// one during a code_editor run. Switches to the file's workspace first --
    /// the pane can only show the active one.
    func revealInEditor(workspaceId: String) {
        if activeWorkspaceId != workspaceId, workspaces.contains(where: { $0.id == workspaceId }) {
            activeWorkspaceId = workspaceId
            activeSessionId = Self.defaultSessionId
        }
        editorRevealRequests += 1
    }

    init(sender: UserInputSender) {
        self.sender = sender
        workspaces = [ClientWorkspace(id: Self.defaultWorkspaceId, name: Self.casualSessionTitle, projectPath: nil)]
        activeWorkspaceId = Self.defaultWorkspaceId
        activeSessionId = Self.defaultSessionId
        seedDefaultSession(forWorkspace: Self.defaultWorkspaceId)
    }

    private func seedDefaultSession(forWorkspace workspaceId: String) {
        let key = SessionKey(workspaceId: workspaceId, sessionId: Self.defaultSessionId)
        sessionsByKey[key] = ChatSession(id: Self.defaultSessionId, workspaceId: workspaceId, title: Self.casualSessionTitle, origin: .user)
        sessionOrder.append(key)
    }

    /// Sessions under `workspaceId`, oldest first.
    func sessions(in workspaceId: String) -> [ChatSession] {
        sessionOrder.compactMap { $0.workspaceId == workspaceId ? sessionsByKey[$0] : nil }
    }

    func session(workspaceId: String, sessionId: String) -> ChatSession? {
        sessionsByKey[SessionKey(workspaceId: workspaceId, sessionId: sessionId)]
    }

    /// Feed for BridgeMessageRouter.onClientUpdate -- the four workspace ->
    /// pet-app confirmation messages (protocol 3.4/3.5). Anything else is a
    /// caller error (BridgeMessageRouter never routes other kinds here).
    func handleClientUpdate(_ message: BridgeMessage) {
        switch message {
        case .workspaceCreate(let workspaceId, let name, let projectPath):
            // Idempotent, for the same reason session_create below is: this
            // arrives both when a workspace is created and when pet-app
            // replays its registry on connect (2026-08-15), and the replay
            // includes the "default" workspace this store already seeded for
            // itself. Appending blindly duplicated every sidebar row on
            // reconnect. A repeat updates in place instead -- name and project
            // path can legitimately have changed since.
            if let index = workspaces.firstIndex(where: { $0.id == workspaceId }) {
                workspaces[index].name = name
                workspaces[index].projectPath = projectPath
                workspaces[index].refreshEditorAvailability()
            } else {
                workspaces.append(ClientWorkspace(id: workspaceId, name: name, projectPath: projectPath))
                seedDefaultSession(forWorkspace: workspaceId)
            }

        case .sessionCreate(let workspaceId, let sessionId, let title, let origin):
            let key = SessionKey(workspaceId: workspaceId, sessionId: sessionId)
            // Idempotent: F15's own agent announces its task session on the
            // socket *and* moves the turn into it locally (moveTurnToTaskSession),
            // and pet-app relays the announcement back to this very app -- so
            // the same session_create legitimately arrives twice. Re-creating
            // would wipe the messages already moved in and duplicate the
            // sidebar row.
            if sessionsByKey[key] == nil {
                sessionsByKey[key] = ChatSession(id: sessionId, workspaceId: workspaceId, title: title, origin: origin)
                sessionOrder.append(key)
            }
            if origin == .agent {
                // The agent branching a casual chat into a task
                // session should bring the user along automatically, not
                // leave them to notice a new sidebar entry on their own.
                activeWorkspaceId = workspaceId
                activeSessionId = sessionId
            }

        default:
            break
        }
    }

    /// The agent decided this turn is real work and opened a task session for
    /// it (F15 open_task_session, 2026-08-12). This is a **move**, not a
    /// branch: the session the prompt was typed into should close once the
    /// task session takes over, not linger alongside it.
    ///
    /// - the user's own message goes with it, because ChatView echoed it into
    ///   the source session locally and it would otherwise vanish with that
    ///   session, leaving the task session open with nothing in it
    /// - the source chat is closed, *unless* it is the workspace's casual
    ///   session: 02_pet-app.md F13 has `session_id: "default"` always
    ///   present, and closing it would also throw away conversation that has
    ///   nothing to do with this task
    ///
    /// Called locally rather than driven off the socket because there is no
    /// "session closed" message in protocol 3.4 -- only create. Nothing else
    /// owns a session list, so nothing else needs telling.
    func moveTurnToTaskSession(
        workspaceId: String,
        from sourceSessionId: String,
        to sessionId: String,
        title: String,
        userMessage: String
    ) {
        let key = SessionKey(workspaceId: workspaceId, sessionId: sessionId)
        if sessionsByKey[key] == nil {
            sessionsByKey[key] = ChatSession(id: sessionId, workspaceId: workspaceId, title: title, origin: .agent)
            sessionOrder.append(key)
        }
        if !userMessage.isEmpty {
            sessionsByKey[key]?.appendUserMessage(userMessage)
        }

        activeWorkspaceId = workspaceId
        activeSessionId = sessionId

        guard sourceSessionId != Self.defaultSessionId, sourceSessionId != sessionId else { return }
        // sessionOrder/sessionsByKey aren't @Published (the sidebar reads them
        // through sessions(in:)), so the removal has to announce itself.
        objectWillChange.send()
        let sourceKey = SessionKey(workspaceId: workspaceId, sessionId: sourceSessionId)
        sessionsByKey.removeValue(forKey: sourceKey)
        sessionOrder.removeAll { $0 == sourceKey }
    }

    private func updateWorkspace(_ workspaceId: String, _ mutate: (inout ClientWorkspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        mutate(&workspaces[index])
    }

    /// Re-resolves a workspace's EditorAvailability against the filesystem
    /// right now -- ClientWorkspace.init already does this once at
    /// creation, so this is only needed for the two cases where the
    /// on-disk state can change out from under an already-created
    /// workspace: right before the editor toggle opens (a stale answer from
    /// creation time would otherwise persist for the workspace's whole
    /// lifetime) and when EditorPaneView's live watcher reports the open
    /// project's root itself was moved/deleted.
    func refreshEditorAvailability(forWorkspace workspaceId: String) {
        updateWorkspace(workspaceId) { $0.refreshEditorAvailability() }
    }

    /// Feed for BridgeMessageRouter.onChatEvent. A session that doesn't exist
    /// yet (e.g. an event racing ahead of its session_create) is dropped
    /// rather than fabricated with guessed metadata.
    func handleChatEvent(_ event: BridgeEvent, workspaceId: String, sessionId: String) {
        session(workspaceId: workspaceId, sessionId: sessionId)?.apply(event)
    }

    @discardableResult
    func requestNewWorkspace(name: String, projectPath: String?) -> UserInputDelivery {
        sender.createWorkspace(name: name, projectPath: projectPath)
    }

    @discardableResult
    func requestNewSession(title: String, in workspaceId: String) -> UserInputDelivery {
        sender.createSession(workspaceId: workspaceId, title: title)
    }

    /// Routes through whichever workspace/session is currently active.
    @discardableResult
    func sendMessage(_ text: String, source: UserInput.Source, attachments: [Attachment]? = nil) -> UserInputDelivery {
        if let onUserCommand {
            onUserCommand(text, activeWorkspaceId, activeSessionId)
            // Not `.notDelivered`: the agent is right here, so the
            // "워크스페이스가 꺼져 있어요" banner would be a lie even though no
            // workspace is connected.
            return .sent
        }
        return sender.send(text: text, source: source, workspaceId: activeWorkspaceId, sessionId: activeSessionId, attachments: attachments)
    }

    /// Shows text the user typed *somewhere else* (pet-app's quick-capture
    /// bubble, mirrored over the socket as user_input) in this window's chat,
    /// and switches to the session it was sent to -- submitting from the
    /// quick-capture bubble should bring this window up showing what was
    /// typed. Messages sent from this window's own input bar are echoed
    /// by ChatView instead; those never come back over the socket.
    ///
    /// - Returns: whether it landed in an existing session (an unknown
    ///   workspace/session is dropped rather than fabricated, same rule as
    ///   handleChatEvent).
    @discardableResult
    func showUserMessage(_ text: String, workspaceId: String?, sessionId: String?) -> Bool {
        let workspaceId = workspaceId ?? Self.defaultWorkspaceId
        let sessionId = sessionId ?? Self.defaultSessionId
        guard let session = session(workspaceId: workspaceId, sessionId: sessionId) else { return false }
        session.appendUserMessage(text)
        activeWorkspaceId = workspaceId
        activeSessionId = sessionId
        return true
    }

    @discardableResult
    func respondToPendingApproval(in session: ChatSession, approved: Bool) -> UserInputDelivery? {
        guard let approvalId = session.pendingApproval?.approvalId else { return nil }
        if let onApprovalResolved {
            onApprovalResolved(approvalId, approved)
            return .sent
        }
        return sender.respondToApproval(approvalId: approvalId, approved: approved)
    }

    @discardableResult
    func cancelActiveRun() -> UserInputDelivery {
        if let onRunCancelled {
            onRunCancelled()
            return .sent
        }
        return sender.cancelRun(sessionId: activeSessionId)
    }
}

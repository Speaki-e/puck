//
//  ClientChatBridge.swift
//  Puck
//
//  F13 chat rebuild · owner: 박해영 (Haeyoung Park)
//  The coordinator between ClientChatWebView's WKWebView and
//  ClientWindowStore/ChatSession, which stay the real source of truth
//  exactly as they were for the native SwiftUI chat -- this class is a
//  second consumer of the same mutations, not a replacement store.
//
//  ClientWindowStore isn't Combine-observed here: sessionOrder/sessionsByKey
//  (the session list itself) aren't @Published, only individual fields like
//  `workspaces` are, so a passive subscription would silently miss session
//  create/move events. Instead AppDelegate calls this bridge's push methods
//  imperatively, right alongside each existing ClientWindowStore mutation
//  call it already makes -- see AppDelegate.swift's `handle(_ message:)` and
//  the `agentHost.onTaskSessionOpened` closure.
//

import AppKit
import WebKit

@MainActor
final class ClientChatBridge: NSObject, WKScriptMessageHandler {
    private let store: ClientWindowStore
    private weak var webView: WKWebView?
    private(set) var isEditorOpen = false
    private var editorOpenChangeHandler: ((Bool) -> Void)?

    init(store: ClientWindowStore) {
        self.store = store
    }

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    /// ClientWindowView calls this once, to learn when the toggle it's
    /// driving flips (so it can swap the native HSplitView layout) -- same
    /// role the old `@State isEditorOpen` played, just externalized here so
    /// the web sidebar's toggle button and the native layout share one
    /// source of truth instead of two.
    func setEditorOpenChangeHandler(_ handler: @escaping (Bool) -> Void) {
        editorOpenChangeHandler = handler
    }

    /// Mirrors ClientWindowView's old `.onChange(of: activeWorkspaceId)`
    /// guard: switching to (or starting on) a workspace that can't open an
    /// editor must not leave the toggle silently on.
    func resetEditorOpenIfUnavailable() {
        if activeWorkspace()?.canOpenEditor != true { setEditorOpen(false) }
    }

    // MARK: - Incoming (JS -> Swift)

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = try? JSONSerialization.data(withJSONObject: message.body),
              let action = try? ChatBridgeAction.decode(from: data) else { return }
        Task { @MainActor in self.handle(action) }
    }

    private func handle(_ action: ChatBridgeAction) {
        switch action {
        case .ready:
            pushHydrate()

        case .sendMessage(let payload):
            store.sendMessage(payload.text, source: .text)

        case .newSession(let payload):
            store.requestNewSession(title: payload.title, in: payload.workspaceId)

        case .newWorkspace(let payload):
            store.requestNewWorkspace(name: payload.name, projectPath: payload.projectPath)

        case .chooseProjectFolder:
            presentFolderPicker()

        case .switchWorkspace(let payload):
            store.activeWorkspaceId = payload.workspaceId
            // Same reset ClientSidebarView's workspace switcher already did:
            // a workspace switch always lands on that workspace's casual
            // session, never a remembered last-session.
            store.activeSessionId = ClientWindowStore.defaultSessionId
            resetEditorOpenIfUnavailable()
            pushWorkspaces()
            pushActiveSession()

        case .switchSession(let payload):
            store.activeWorkspaceId = payload.workspaceId
            store.activeSessionId = payload.sessionId
            pushActiveSession()

        case .respondApproval(let payload):
            guard let session = store.session(workspaceId: payload.workspaceId, sessionId: payload.sessionId) else { return }
            store.respondToPendingApproval(in: session, approved: payload.approved)

        case .cancelRun:
            store.cancelActiveRun()

        case .toggleEditor:
            setEditorOpen(!isEditorOpen)

        case .openSettings:
            // Same nil-target responder-chain send ClientWindowView's old
            // settings button used -- see that file's own comment on why.
            NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
        }
    }

    private func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            let path = response == .OK ? panel.url?.path : nil
            self?.push(type: "state:projectFolderChosen", payload: ProjectFolderChosenPayload(path: path))
        }
    }

    private func setEditorOpen(_ isOpen: Bool) {
        isEditorOpen = isOpen
        editorOpenChangeHandler?(isOpen)
        pushEditorOpen()
    }

    // MARK: - Outgoing (Swift -> JS)

    private func activeWorkspace() -> ClientWorkspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private func activeSession() -> ChatSession? {
        store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId)
    }

    func pushHydrate() {
        let payload = HydratePayload(
            themeStyle: store.themeStyle.rawValue,
            workspaces: store.workspaces.map(WorkspaceJSON.init),
            activeWorkspaceId: store.activeWorkspaceId,
            activeSessionId: store.activeSessionId,
            sessionsByWorkspace: Dictionary(uniqueKeysWithValues: store.workspaces.map { workspace in
                (workspace.id, store.sessions(in: workspace.id).map(SessionSummaryJSON.init))
            }),
            activeSession: activeSession().map(SessionStateJSON.init),
            editorOpen: isEditorOpen
        )
        push(type: "state:hydrate", payload: payload)
    }

    private func pushWorkspaces() {
        push(type: "state:workspaces", payload: WorkspacesPayload(workspaces: store.workspaces.map(WorkspaceJSON.init), activeWorkspaceId: store.activeWorkspaceId))
    }

    private func pushSessions(for workspaceId: String) {
        push(type: "state:sessions", payload: SessionsPayload(workspaceId: workspaceId, sessions: store.sessions(in: workspaceId).map(SessionSummaryJSON.init)))
    }

    private func pushActiveSession() {
        push(type: "state:activeSession", payload: ActiveSessionPayload(session: activeSession().map(SessionStateJSON.init)))
    }

    private func pushEditorOpen() {
        push(type: "state:editorOpen", payload: EditorOpenPayload(isOpen: isEditorOpen, canOpen: activeWorkspace()?.canOpenEditor ?? false))
    }

    /// Called from AppDelegate after any ClientWindowStore mutation that
    /// isn't a chat event -- new workspace, new/moved session, editor URL
    /// arriving. Deliberately a blanket resend (all workspaces' session
    /// lists + the active session) rather than tracking exactly which
    /// workspace changed: these events are infrequent enough that the
    /// simplicity is worth more than the marginal bandwidth.
    func refreshWorkspacesAndSessions() {
        resetEditorOpenIfUnavailable()
        pushWorkspaces()
        for workspace in store.workspaces { pushSessions(for: workspace.id) }
        pushActiveSession()
        pushEditorOpen()
    }

    /// F14 quick-capture bubble echo (AppDelegate's `.userInput` case) --
    /// the message already landed in the session via
    /// ClientWindowStore.showUserMessage before this is called, so this just
    /// announces the row that appended.
    func pushUserMessageEcho(workspaceId: String, sessionId: String) {
        guard let session = store.session(workspaceId: workspaceId, sessionId: sessionId), let last = session.timeline.last else { return }
        push(type: "session:timelineAppend", payload: TimelineAppendPayload(workspaceId: workspaceId, sessionId: sessionId, entry: TimelineEntryJSON(last)))
    }

    /// Replaces AppDelegate's direct `ClientWindowStore.handleChatEvent` call
    /// for chat events -- folds the event into the session itself (via the
    /// store) and pushes the exact delta, in that order. Order matters for
    /// `.textChunk`: whether to append-in-place or start a new entry can
    /// only be answered from the *pre-fold* state (was the last entry
    /// already assistantText?), while the id of a *new* entry can only be
    /// read *post*-fold (ChatSession mints it internally) -- so this method
    /// captures the "before" answer, folds, then reads "after" once, rather
    /// than reimplementing ChatSession.apply's own decision from scratch
    /// (docs/decisions.md: the streaming append/insert rule must not exist
    /// in two places that can drift).
    func applyEvent(_ event: BridgeEvent, workspaceId: String, sessionId: String) {
        guard let session = store.session(workspaceId: workspaceId, sessionId: sessionId) else {
            store.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
            return
        }

        let previousAssistantTextId: String? = {
            if case .assistantText(let id, _) = session.timeline.last { return id.uuidString }
            return nil
        }()

        store.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)

        switch event {
        case .agentThinking:
            push(type: "session:runningChanged", payload: RunningChangedPayload(workspaceId: workspaceId, sessionId: sessionId, isRunning: true))

        case .textChunk(let text):
            if let previousAssistantTextId {
                push(type: "session:textChunk", payload: TextChunkPayload(workspaceId: workspaceId, sessionId: sessionId, entryId: previousAssistantTextId, delta: text, append: true))
            } else if case .assistantText(let newId, _) = session.timeline.last {
                push(type: "session:textChunk", payload: TextChunkPayload(workspaceId: workspaceId, sessionId: sessionId, entryId: newId.uuidString, delta: text, append: false))
            }
            push(type: "session:runningChanged", payload: RunningChangedPayload(workspaceId: workspaceId, sessionId: sessionId, isRunning: true))

        case .toolCall, .toolResult:
            guard let last = session.timeline.last else { return }
            push(type: "session:timelineAppend", payload: TimelineAppendPayload(workspaceId: workspaceId, sessionId: sessionId, entry: TimelineEntryJSON(last)))

        case .awaitApproval(let summary, let approvalId):
            push(type: "session:pendingApproval", payload: PendingApprovalChangedPayload(workspaceId: workspaceId, sessionId: sessionId, approval: PendingApprovalJSON(approvalId: approvalId, summary: summary)))

        case .agentDone:
            push(type: "session:runningChanged", payload: RunningChangedPayload(workspaceId: workspaceId, sessionId: sessionId, isRunning: false))
            push(type: "session:pendingApproval", payload: PendingApprovalChangedPayload(workspaceId: workspaceId, sessionId: sessionId, approval: nil))
            guard let last = session.timeline.last else { return }
            push(type: "session:timelineAppend", payload: TimelineAppendPayload(workspaceId: workspaceId, sessionId: sessionId, entry: TimelineEntryJSON(last)))
        }
    }

    private func push<Payload: Encodable>(type: String, payload: Payload) {
        guard let webView else { return }
        let envelope = BridgeOutboundEnvelope(type: type, payload: payload)
        guard let data = try? JSONEncoder().encode(envelope), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.PuckChatBridge && window.PuckChatBridge.receive(\(json));")
    }
}

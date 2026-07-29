//
//  ClientWindowStore.swift
//  PetAgent
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
    /// Not localized yet -- ClientWindowStore has no AppLanguage dependency.
    /// Revisit when the sidebar (F13 UI) is built and can supply one.
    private static let casualSessionTitle = "Casual"

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

    @Published private(set) var workspaces: [ClientWorkspace]
    @Published var activeWorkspaceId: String
    @Published var activeSessionId: String

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
            workspaces.append(ClientWorkspace(id: workspaceId, name: name, projectPath: projectPath))
            seedDefaultSession(forWorkspace: workspaceId)

        case .sessionCreate(let workspaceId, let sessionId, let title, let origin):
            let key = SessionKey(workspaceId: workspaceId, sessionId: sessionId)
            sessionsByKey[key] = ChatSession(id: sessionId, workspaceId: workspaceId, title: title, origin: origin)
            sessionOrder.append(key)
            if origin == .agent {
                // byeolki: the agent branching a casual chat into a task
                // session should bring the user along automatically, not
                // leave them to notice a new sidebar entry on their own.
                activeWorkspaceId = workspaceId
                activeSessionId = sessionId
            }

        case .editorViewReady(let workspaceId, let url):
            updateWorkspace(workspaceId) {
                $0.editorViewURL = URL(string: url)
                $0.editorUnavailableReason = nil
            }

        case .editorViewUnavailable(let workspaceId, let reason):
            updateWorkspace(workspaceId) {
                $0.editorViewURL = nil
                $0.editorUnavailableReason = reason
            }

        default:
            break
        }
    }

    private func updateWorkspace(_ workspaceId: String, _ mutate: (inout ClientWorkspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        mutate(&workspaces[index])
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
        sender.send(text: text, source: source, workspaceId: activeWorkspaceId, sessionId: activeSessionId, attachments: attachments)
    }

    @discardableResult
    func respondToPendingApproval(in session: ChatSession, approved: Bool) -> UserInputDelivery? {
        guard let approvalId = session.pendingApproval?.approvalId else { return nil }
        return sender.respondToApproval(approvalId: approvalId, approved: approved)
    }

    @discardableResult
    func cancelActiveRun() -> UserInputDelivery {
        sender.cancelRun(sessionId: activeSessionId)
    }
}

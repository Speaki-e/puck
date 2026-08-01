//
//  ClientWindowStore.swift
//  Shaydi
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
    /// Korean-only, matching the rest of the app's UI text.
    private static let casualSessionTitle = "Casual"

    /// Sessions are keyed on (workspaceId, sessionId), not sessionId alone:
    /// every workspace gets its own "default" casual session (see
    /// seedDefaultSession), so session_id is only unique within a workspace.
    private struct SessionKey: Hashable {
        let workspaceId: String
        let sessionId: String
    }

    private let sender: UserInputSender
    private let defaults: UserDefaults
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

    private static let themeStyleDefaultsKey = ClientThemeStyle.defaultsKey

    /// byeolki, 2026-08-01: "테마 종류를 다크, 화이트, 글래스로" -- an in-app
    /// theme setting independent of Shaydi's own system-wide AppAppearance
    /// (the pet overlay/Notch/Settings' light/dark/system toggle). Persisted
    /// in whichever UserDefaults domain this store was given (ShaydiAgent's
    /// own by default) -- unlike the appearance property this replaces,
    /// nothing about this needs to be read cross-process from Shaydi, so no
    /// DistributedNotificationCenter broadcast is involved.
    @Published var themeStyle: ClientThemeStyle {
        didSet {
            defaults.set(themeStyle.rawValue, forKey: Self.themeStyleDefaultsKey)
            onThemeStyleChanged?(themeStyle)
        }
    }
    /// AppDelegate uses this to keep NSApp.appearance (and therefore
    /// NSVisualEffectView materials / native popover chrome, none of which
    /// SwiftUI's .preferredColorScheme touches) in sync with the resolved
    /// theme -- same reasoning AppAppearance's own doc comment already
    /// documents for the pattern this mirrors.
    var onThemeStyleChanged: ((ClientThemeStyle) -> Void)?

    init(sender: UserInputSender, defaults: UserDefaults = .standard) {
        self.sender = sender
        self.defaults = defaults
        workspaces = [ClientWorkspace(id: Self.defaultWorkspaceId, name: Self.casualSessionTitle, projectPath: nil)]
        activeWorkspaceId = Self.defaultWorkspaceId
        activeSessionId = Self.defaultSessionId
        themeStyle = ClientThemeStyle.resolved(fromDefaultsValue: defaults.string(forKey: Self.themeStyleDefaultsKey))
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
        if let onUserCommand {
            onUserCommand(text, activeWorkspaceId, activeSessionId)
            // Not `.workspaceDisconnected`: the agent is right here, so the
            // "워크스페이스가 꺼져 있어요" banner would be a lie even though no
            // workspace is connected.
            return .sent
        }
        return sender.send(text: text, source: source, workspaceId: activeWorkspaceId, sessionId: activeSessionId, attachments: attachments)
    }

    /// Shows text the user typed *somewhere else* (pet-app's quick-capture
    /// bubble, mirrored over the socket as user_input) in this window's chat,
    /// and switches to the session it was sent to -- byeolki, 2026-07-30:
    /// "입력창에 내용을 작성하면 창이 새로 열리면서 ... 입력한 내용이
    /// 보여지게". Messages sent from this window's own input bar are echoed
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

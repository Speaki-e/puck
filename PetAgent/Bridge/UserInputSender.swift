//
//  UserInputSender.swift
//  PetAgent
//
//  F6/F7 · owner: 박해영 (Haeyoung Park)
//  Sends protocol 3.3 user_input, and tells the caller when it couldn't.
//
//  AppDelegate used to cache the last BridgeConnection handed to it by
//  BridgeServer.onMessage and never clear it, so once workspace disconnected
//  the app still believed it had a client: it wrote into a cancelled socket
//  and the input vanished with no feedback. F6 requires a "워크스페이스
//  꺼져있음" bubble in exactly that case, which needs the send to report
//  failure rather than pretend.
//

import Foundation

/// What pet-app needs from the socket layer in order to send user input.
/// Kept narrow so the decision is testable without Network.framework.
protocol UserInputTransport: AnyObject {
    /// Live state, not a remembered one — a client that disconnected must
    /// stop counting immediately.
    var hasConnectedClients: Bool { get }
    /// - Returns: whether the message actually reached >=1 live connection.
    ///   `hasConnectedClients` is only a pre-flight check; a client can
    ///   disconnect between that check and this call (BridgeConnection.onClose
    ///   races in on BridgeServer's own queue), so delivery is decided from
    ///   this return value, not the earlier snapshot.
    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool
}

enum UserInputDelivery: Equatable {
    case sent
    /// Nothing is listening: the socket server never started, or workspace
    /// is not connected (or has since gone away).
    case workspaceDisconnected
}

final class UserInputSender {
    private let transport: () -> UserInputTransport?

    /// - Parameter transport: resolved per send, so connection state is read
    ///   fresh every time instead of captured once.
    init(transport: @escaping () -> UserInputTransport?) {
        self.transport = transport
    }

    /// - Parameters:
    ///   - workspaceId/sessionId: F13 (2026-07-29, protocol 3.4) -- default to
    ///     nil (wire default "default") for callers that don't yet know about
    ///     workspaces/sessions.
    @discardableResult
    func send(
        text: String,
        source: UserInput.Source,
        workspaceId: String? = nil,
        sessionId: String? = nil,
        attachments: [Attachment]? = nil
    ) -> UserInputDelivery {
        broadcast(.userInput(UserInput(text: text, source: source, workspaceId: workspaceId, sessionId: sessionId, attachments: attachments)))
    }

    /// F13 (2026-07-29, protocol 3.4): request a new workspace via the
    /// sidebar's "add workspace". Confirmed later by a workspace_create
    /// BridgeMessageRouter.onClientUpdate callback, which is the one that
    /// actually assigns workspace_id.
    @discardableResult
    func createWorkspace(name: String, projectPath: String?) -> UserInputDelivery {
        broadcast(.workspaceCreateRequest(name: name, projectPath: projectPath))
    }

    /// F13 (2026-07-29, protocol 3.4): request a new chat session via the
    /// sidebar's "new chat". Confirmed later by a session_create
    /// onClientUpdate callback (origin: .user).
    @discardableResult
    func createSession(workspaceId: String, title: String) -> UserInputDelivery {
        broadcast(.sessionCreateRequest(workspaceId: workspaceId, title: title))
    }

    /// F13 (2026-07-29, protocol 3.6): resolve a pending await_approval from
    /// the chat view's allow/deny buttons.
    @discardableResult
    func respondToApproval(approvalId: String, approved: Bool) -> UserInputDelivery {
        broadcast(.approvalResponse(approvalId: approvalId, approved: approved))
    }

    /// F13 (2026-07-29, protocol 3.6): the chat view's stop button -- aborts
    /// the whole conversation turn, not a single tool (see ToolCancel for that).
    @discardableResult
    func cancelRun(sessionId: String) -> UserInputDelivery {
        broadcast(.runCancel(sessionId: sessionId))
    }

    private func broadcast(_ message: BridgeMessage) -> UserInputDelivery {
        guard let transport = transport(), transport.hasConnectedClients else {
            return .workspaceDisconnected
        }
        let delivered = transport.broadcast(message)
        return delivered ? .sent : .workspaceDisconnected
    }
}

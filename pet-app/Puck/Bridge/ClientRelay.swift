//
//  ClientRelay.swift
//  Puck
//
//  F13/socket · owner: 박해영 (Haeyoung Park)
//  Which connection role a BridgeMessage should be forwarded to, now that
//  the client window is its own process (PuckClient) rather than living
//  in-process with pet-app (2026-07-30, protocol 3.7). Pure and
//  Network.framework-independent so BridgeServer's relay wiring stays
//  testable without a real socket.
//

enum ClientRelay {
    /// - Returns: the role a message should be relayed to, or nil for
    ///   messages BridgeMessageRouter already handles locally (tool_dispatch/
    ///   tool_cancel/tool_result never cross the gui/workspace boundary) or
    ///   that are connection-lifecycle only (client_hello).
    static func targetRole(for message: BridgeMessage) -> ClientRole? {
        switch message {
        case .userInput, .approvalResponse, .runCancel:
            return .workspace

        case .event, .workspaceCreate, .sessionCreate, .editorViewReady, .editorViewUnavailable:
            return .gui

        // workspace_create_request / session_create_request stopped going
        // outward on 2026-08-15: BridgeMessageRouter answers them from the
        // in-process WorkspaceRegistry instead. Relaying them as well would
        // create a second, competing workspace id for the same click.
        case .workspaceCreateRequest, .sessionCreateRequest,
             .clientHello, .toolDispatch, .toolCancel, .toolResult:
            return nil
        }
    }
}

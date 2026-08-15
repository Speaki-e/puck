//
//  WorkspaceCoordinator.swift
//  Puck
//
//  Turns PuckClient's workspace_create_request / session_create_request into
//  the workspace_create / session_create confirmations that answer them.
//
//  This round trip used to leave the process: pet-app relayed both requests to
//  workspace (Electron), which owned the registries and sent the confirmation
//  back (workspace/src/main/app/pet-bridge-router.ts). Now that the registries
//  live here, the request never reaches the socket at all -- it is answered
//  where it lands. The *messages* are unchanged, so PuckClient and chat-web
//  need no changes.
//
//  Port note: parity with the TS handler includes its failure mode. A project
//  path that can't be used produces no confirmation, only a log line -- the
//  alternative, confirming a workspace whose project path was quietly dropped,
//  is indistinguishable downstream from a chat-only workspace.
//
//  Main-thread only, like the registries it owns.
//

import Foundation

final class WorkspaceCoordinator {
    private let workspaces: WorkspaceRegistry
    private let sessions: SessionRegistry
    private let log: (String) -> Void

    init(
        workspaces: WorkspaceRegistry,
        sessions: SessionRegistry = SessionRegistry(),
        log: @escaping (String) -> Void = { AppLogger.shared.log(.error, $0) }
    ) {
        self.workspaces = workspaces
        self.sessions = sessions
        self.log = log
    }

    /// - Returns: the confirmations to broadcast to gui connections, in order,
    ///   or an empty array when the request could not be honoured. Returning
    ///   messages rather than sending them keeps this testable without a socket
    ///   (the same reason ClientRelay is a pure function).
    func handle(_ message: BridgeMessage) -> [BridgeMessage] {
        switch message {
        case .workspaceCreateRequest(let name, let projectPath):
            return createWorkspace(name: name, projectPath: projectPath)

        case .sessionCreateRequest(let workspaceId, let title):
            return [createSession(workspaceId: workspaceId, title: title)]

        default:
            return []
        }
    }

    private func createWorkspace(name: String, projectPath: String?) -> [BridgeMessage] {
        do {
            let record = try workspaces.create(name: name, projectPath: projectPath)
            return [.workspaceCreate(
                workspaceId: record.id,
                name: record.name,
                projectPath: record.realProjectPath
            )]
        } catch {
            log("WorkspaceCoordinator: workspace_create_request failed (\(error)) for path \(projectPath ?? "none")")
            return []
        }
    }

    private func createSession(workspaceId: String, title: String) -> BridgeMessage {
        // Unknown workspace ids fall back to default rather than failing: the
        // TS handler did the same (stringField(..., "default")), and a chat
        // that can't be started is worse than one started in the wrong place.
        let resolvedWorkspaceId = workspaces.get(id: workspaceId) != nil
            ? workspaceId
            : WorkspaceRegistry.defaultWorkspaceID
        let record = sessions.record(workspaceId: resolvedWorkspaceId, title: title, origin: .user)
        return .sessionCreate(
            workspaceId: resolvedWorkspaceId,
            sessionId: record.id,
            title: record.title,
            origin: .user
        )
    }
}

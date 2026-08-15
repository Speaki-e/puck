//
//  BridgeMessageRouter.swift
//  Puck
//
//  F11/socket · owner: 박해영 (Haeyoung Park)
//  Routes an incoming BridgeMessage to tool execution or an FSM/SFX reaction,
//  hopping onto the main thread first.
//
//  BridgeServer delivers messages on its own background queue, but everything
//  downstream of here is main-thread-only:
//    - EventRouter reactions drive CharacterController -> SpriteAvatar, i.e.
//      CALayer/AppKit mutation, which is not safe off the main thread.
//    - pet-app-executor handlers read NSWorkspace and WindowListWatcher.windows,
//      the latter being mutated by a 10Hz timer that runs on main.
//  Handlers that do genuinely slow work (RunShellHandler, RunAppleScriptHandler)
//  hop onto their own background queue internally, so this does not park long
//  work on main.
//

import Foundation

final class BridgeMessageRouter {
    private let toolExecutor: ToolExecutor
    private let dispatchToMain: (@escaping () -> Void) -> Void
    /// EventRouter.reaction(for:) is a pure function with no session state of
    /// its own (per its header) -- this is the one place that lives, so a
    /// code_editor tool_call can detect its detail.path *changing* across
    /// calls (02_pet-app.md F3: "detail.path 변경 시 짧은 점프"). Read/written
    /// only from `handle`, which always runs on main via dispatchToMain.
    private var lastCodeEditorPath: String?

    /// Emitted for protocol 3.2 status events, already on the main thread.
    var onEventReaction: ((EventReaction) -> Void)?

    /// Emitted for the workspace/session/editor-view confirmations workspace
    /// sends pet-app (protocol 3.4/3.5, 2026-07-29) -- workspace_create,
    /// session_create, editor_view_ready, editor_view_unavailable. Already on
    /// the main thread, like onEventReaction. F13's client-window store (task
    /// #134) is the intended consumer; kept as the raw BridgeMessage rather
    /// than a bespoke type since this router shouldn't need to know that
    /// store's shape.
    var onClientUpdate: ((BridgeMessage) -> Void)?

    /// Emitted for every protocol 3.2 event, alongside onEventReaction --
    /// F13's ClientWindowStore (2026-07-29) folds the raw event into the
    /// right session's chat timeline (ChatSession.apply), which needs the
    /// full event and its workspace_id/session_id, not just the derived pet
    /// EventReaction onEventReaction carries.
    var onChatEvent: ((BridgeEvent, _ workspaceId: String, _ sessionId: String) -> Void)?

    /// Answers workspace_create_request / session_create_request locally.
    /// Left optional so the many tests that only care about tool dispatch or
    /// event reactions can keep constructing a router with one argument.
    var workspaceCoordinator: WorkspaceCoordinator?

    /// Where the confirmations produced by `workspaceCoordinator` go -- every
    /// gui connection, which is what BridgeServer.relay did for them back when
    /// workspace was the sender. Already on the main thread.
    var onWorkspaceConfirmation: ((BridgeMessage) -> Void)?

    /// - Parameter dispatchToMain: injected so tests can observe the hop.
    ///   Defaults to an async hop to the main queue; it stays async even when
    ///   already on main so ordering is identical from every caller.
    init(
        toolExecutor: ToolExecutor,
        dispatchToMain: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }
    ) {
        self.toolExecutor = toolExecutor
        self.dispatchToMain = dispatchToMain
    }

    /// - Parameter reply: how to send a message back to the client this one
    ///   arrived on. Kept as a closure rather than a BridgeConnection so this
    ///   type stays independent of Network.framework (and testable without a
    ///   live socket).
    func handle(_ message: BridgeMessage, reply: @escaping (BridgeMessage) -> Void) {
        switch message {
        case .toolDispatch(let dispatch):
            dispatchToMain { [toolExecutor] in
                toolExecutor.dispatch(dispatch) { result in
                    reply(.toolResult(result))
                }
            }

        case .toolCancel(let id):
            // No reply of its own -- the cancelled dispatch's original id
            // replies error="cancelled" through its own completion.
            dispatchToMain { [toolExecutor] in
                toolExecutor.cancel(id: id)
            }

        case .event(let event, let workspaceId, let sessionId):
            dispatchToMain { [weak self] in
                guard let self else { return }
                let reaction = EventRouter.reaction(for: event, previousCodeEditorPath: self.lastCodeEditorPath)
                if case .toolCall(_, let tool, _, let detail) = event, tool == "code_editor" {
                    self.lastCodeEditorPath = EventRouter.codeEditorPath(from: detail) ?? self.lastCodeEditorPath
                }
                self.onEventReaction?(reaction)
                self.onChatEvent?(event, workspaceId, sessionId)
            }

        case .workspaceCreate, .sessionCreate, .editorViewReady, .editorViewUnavailable:
            dispatchToMain { [weak self] in
                self?.onClientUpdate?(message)
            }

        case .workspaceCreateRequest, .sessionCreateRequest:
            // Answered in-process as of 2026-08-15 -- WorkspaceRegistry lives
            // here now, so these no longer leave for workspace (Electron) and
            // come back. ClientRelay stops routing them outward to match.
            dispatchToMain { [weak self] in
                guard let self, let coordinator = self.workspaceCoordinator else { return }
                for confirmation in coordinator.handle(message) {
                    self.onWorkspaceConfirmation?(confirmation)
                }
            }

        case .toolResult, .userInput, .approvalResponse, .runCancel:
            break // pet-app only ever sends these, never receives them

        case .clientHello:
            break // intercepted by BridgeServer before reaching here (assigns the connection's role)
        }
    }
}

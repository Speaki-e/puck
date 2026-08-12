//
//  CodeEditorDelegate.swift
//  Puck
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  Lets the local agent (AgentRunner) reach the one tool it does not own:
//  code_editor, whose executor is `workspace` (01_protocol.md section 4).
//  byeolki, 2026-08-12: "에디터 ai 랑 pet ai 랑 연동이 되어야함 pet에
//  지시하면 에디터에서 편집이되는 그런" -- with the agent, not the editor, as
//  the product's centre: the pet's brain stays in charge of the conversation
//  and hands coding work off as one tool call among the rest.
//
//  ## Why user_input and not tool_dispatch
//
//  The obvious shape -- put code_editor on the socket the same way
//  PetToolDispatcher puts launch_app on it -- is not legal today:
//  `tool_dispatch` is defined as workspace -> pet-app -> workspace
//  (01_protocol.md 3.1), and pet-app -> workspace has no dispatch direction
//  at all. Adding one is a protocol PR, and the contract comes first.
//
//  `user_input` (3.3) already runs pet-app -> workspace, and what is on the
//  far side of it is workspace's own agent, which owns code_editor and runs
//  it through ACP. So the delegation is: send the task as user_input, let
//  workspace's agent do the editing, and treat its `agent_done` (3.2) as this
//  tool's result. Everything workspace emits along the way -- agent_thinking,
//  text_chunk, its own tool_call(code_editor) -- is already relayed to every
//  gui connection, so the transcript and the pet's Type animation come for
//  free rather than needing anything here.
//
//  ponytail: correlation is by session_id alone, so one delegation per
//  session at a time (a second one while the first is in flight is refused
//  rather than mis-paired). protocol has no request_id yet -- it is a known
//  open item on both sides. When it lands, or when pet-app -> workspace
//  tool_dispatch does, only the inside of this type changes.
//

import Foundation

final class CodeEditorDelegate {
    /// Puts one user_input on the socket. False when nothing is connected --
    /// which for this message means no *workspace* connection, since pet-app
    /// relays user_input to that role only (ClientRelay).
    private let send: (_ task: String, _ workspaceId: String, _ sessionId: String) -> Bool
    private let timeoutSeconds: TimeInterval

    /// sessionId -> the tool call waiting for that session's agent_done.
    private var pending: [String: CheckedContinuation<DispatchedToolResult, Never>] = [:]
    private let lock = NSLock()

    init(
        send: @escaping (_ task: String, _ workspaceId: String, _ sessionId: String) -> Bool,
        timeoutSeconds: TimeInterval = ToolTimeouts.seconds(for: "code_editor")
    ) {
        self.send = send
        self.timeoutSeconds = timeoutSeconds
    }

    func execute(task: String, workspaceId: String, sessionId: String) async -> DispatchedToolResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard pending[sessionId] == nil else {
                lock.unlock()
                continuation.resume(returning: DispatchedToolResult(
                    ok: false,
                    data: nil,
                    error: "execution_failed",
                    detail: "이 세션에서 이미 편집 작업이 진행 중이에요. 끝난 뒤에 다시 요청해 주세요."
                ))
                return
            }
            pending[sessionId] = continuation
            lock.unlock()

            guard send(task, workspaceId, sessionId) else {
                // Same immediate answer PetToolDispatcher gives, and the same
                // reason: no round trip is coming, so waiting out the timeout
                // would only stall the run. The code is the protocol's, read
                // from the agent's side: the far end isn't there.
                resolve(sessionId: sessionId, with: DispatchedToolResult(
                    ok: false,
                    data: nil,
                    error: "pet_app_disconnected",
                    detail: "workspace가 연결돼 있지 않아 코드 편집을 맡길 수 없어요."
                ))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                self?.resolve(sessionId: sessionId, with: DispatchedToolResult(
                    ok: false,
                    data: nil,
                    error: "timeout",
                    detail: "code_editor exceeded \(Int(self?.timeoutSeconds ?? 0))s"
                ))
            }
        }
    }

    /// Feed every event that arrives for a session here. Only `agent_done`
    /// means anything -- it is workspace's "the run finished", which is this
    /// tool's return value. Events for sessions with nothing in flight (the
    /// normal case, including this app's own broadcasts coming back through
    /// the relay) are ignored.
    func handle(_ event: BridgeEvent, sessionId: String) {
        guard case .agentDone(let ok, let summary) = event else { return }
        resolve(sessionId: sessionId, with: DispatchedToolResult(
            ok: ok,
            data: ok ? .string(summary) : nil,
            error: ok ? nil : "execution_failed",
            detail: summary
        ))
    }

    /// The socket dropped, or the user hit 중지: nothing in flight can finish.
    func failAllInFlight(error: String = "pet_app_disconnected", detail: String? = nil) {
        lock.lock()
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        for (_, continuation) in waiting {
            continuation.resume(returning: DispatchedToolResult(ok: false, data: nil, error: error, detail: detail))
        }
    }

    /// Safe to call twice -- the loser (usually the timeout firing after a
    /// real agent_done) finds nothing and does nothing, which is what keeps a
    /// continuation from being resumed twice and trapping.
    private func resolve(sessionId: String, with result: DispatchedToolResult) {
        lock.lock()
        let continuation = pending.removeValue(forKey: sessionId)
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

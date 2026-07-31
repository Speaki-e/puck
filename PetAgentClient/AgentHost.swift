//
//  AgentHost.swift
//  PetAgentClient
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  Wires the agent loop to this app: the chat sends commands in, tool calls
//  go out over bridge.sock, and every step comes back as a BridgeEvent.
//
//  ## Events are broadcast, never applied locally
//
//  A BridgeEvent this app puts on the socket is relayed by pet-app to every
//  gui connection -- including this one, since BridgeServer.relay does not
//  exclude the sender -- while pet-app's own router turns it into the pet's
//  reaction. So broadcasting once makes the pet act *and* the transcript
//  update, through the same path events already took when the plan's
//  workspace process was going to produce them. Applying locally as well
//  would render everything twice.
//

import AppKit

final class AgentHost {
    private let broadcast: (BridgeMessage) -> Bool
    private let dispatcher: PetToolDispatcher
    private var runner: AgentRunner!

    /// approvalId -> the run waiting on the user's answer.
    private var pendingApprovals: [String: CheckedContinuation<Bool, Never>] = [:]
    private let lock = NSLock()

    /// Re-read on every access rather than cached: the key can be typed into
    /// PetAgent's settings panel while this app is running, and the two are
    /// separate processes -- there is no change notification to subscribe to,
    /// only the file both of them read.
    var configuration: AgentConfiguration { .load() }

    /// Where the events of the current run are addressed. Captured when a run
    /// starts so results land in the session the command came from even if
    /// the user switches session mid-run.
    private var activeWorkspaceId = ClientWindowStore.defaultWorkspaceId
    private var activeSessionId = ClientWindowStore.defaultSessionId

    init(broadcast: @escaping (BridgeMessage) -> Bool) {
        self.broadcast = broadcast
        self.dispatcher = PetToolDispatcher(send: broadcast)
        self.runner = AgentRunner(
            client: GPTClient(configuration: { .load() }),
            dispatcher: dispatcher,
            approve: { [weak self] _, approvalId in
                await self?.awaitApproval(id: approvalId) ?? false
            },
            emit: { [weak self] event in
                guard let self else { return }
                _ = self.broadcast(.event(event, workspaceId: self.activeWorkspaceId, sessionId: self.activeSessionId))
            }
        )
    }

    /// Every tool_result off the socket, so the dispatcher can match it to
    /// the call waiting for it.
    func handle(_ result: ToolResult) {
        dispatcher.handle(result)
    }

    /// pet-app went away: nothing in flight can be answered any more.
    func socketDisconnected() {
        dispatcher.failAllInFlight()
    }

    func run(command: String, workspaceId: String, sessionId: String) {
        guard configuration.isConfigured else {
            // Said as a normal agent turn rather than an alert -- it belongs
            // in the transcript next to the message that couldn't be answered.
            // Names the actual paths that were searched rather than "check
            // your config" -- the search order is the answer to the question
            // this message provokes.
            let searched = AgentConfiguration.defaultSearchPaths
                .map { $0.appendingPathComponent(".env").path }
                .joined(separator: "\n")
            let message = """
            OpenAI API 키가 없어요. 아래 중 한 곳의 .env에 OPENAI_API_KEY=... 를 넣어주세요.
            \(searched)
            """
            _ = broadcast(.event(.textChunk(text: message), workspaceId: workspaceId, sessionId: sessionId))
            _ = broadcast(.event(.agentDone(ok: false, summary: message), workspaceId: workspaceId, sessionId: sessionId))
            return
        }

        activeWorkspaceId = workspaceId
        activeSessionId = sessionId
        Task { await runner.run(command: command) }
    }

    /// The chat's 허용/거부 buttons land here.
    func resolveApproval(id: String, approved: Bool) {
        lock.lock()
        let continuation = pendingApprovals.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(returning: approved)
    }

    /// Denies everything still waiting -- used when the run is cancelled, so
    /// a pending approval doesn't strand the loop forever.
    func cancelPendingApprovals() {
        lock.lock()
        let waiting = pendingApprovals
        pendingApprovals.removeAll()
        lock.unlock()
        for (_, continuation) in waiting { continuation.resume(returning: false) }
    }

    private func awaitApproval(id: String) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            pendingApprovals[id] = continuation
            lock.unlock()
        }
    }
}

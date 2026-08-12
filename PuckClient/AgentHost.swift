//
//  AgentHost.swift
//  PuckClient
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
    /// code_editor's executor lives in workspace, so it is delegated over
    /// user_input rather than dispatched -- see CodeEditorDelegate.
    private let codeEditorDelegate: CodeEditorDelegate
    private var runner: AgentRunner!

    /// approvalId -> the run waiting on the user's answer.
    private var pendingApprovals: [String: CheckedContinuation<Bool, Never>] = [:]
    private let lock = NSLock()

    /// Re-read on every access rather than cached: the key can be typed into
    /// Puck's settings panel while this app is running, and the two are
    /// separate processes -- there is no change notification to subscribe to,
    /// only the file both of them read.
    var configuration: AgentConfiguration { .load() }

    /// Where the events of the current run are addressed. Captured when a run
    /// starts so results land in the session the command came from even if
    /// the user switches session mid-run.
    private var activeWorkspaceId = ClientWindowStore.defaultWorkspaceId
    private var activeSessionId = ClientWindowStore.defaultSessionId
    /// What the user typed for the current run, kept so open_task_session can
    /// carry it into the session it moves the turn to.
    private var activeCommand = ""

    /// Set by AppDelegate: the local side of open_task_session, which has no
    /// socket message behind it (protocol 3.4 can create a session but not
    /// close one).
    var onTaskSessionOpened: ((
        _ workspaceId: String,
        _ sourceSessionId: String,
        _ sessionId: String,
        _ title: String,
        _ userMessage: String
    ) -> Void)?

    init(broadcast: @escaping (BridgeMessage) -> Bool) {
        self.broadcast = broadcast
        self.dispatcher = PetToolDispatcher(send: broadcast)
        self.codeEditorDelegate = CodeEditorDelegate(send: { task, workspaceId, sessionId in
            broadcast(.userInput(UserInput(
                text: task,
                source: .text,
                workspaceId: workspaceId,
                sessionId: sessionId,
                attachments: nil
            )))
        })
        self.runner = AgentRunner(
            client: GPTClient(configuration: { .load() }),
            dispatcher: dispatcher,
            approve: { [weak self] _, approvalId in
                await self?.awaitApproval(id: approvalId) ?? false
            },
            emit: { [weak self] event in
                guard let self else { return }
                _ = self.broadcast(.event(event, workspaceId: self.activeWorkspaceId, sessionId: self.activeSessionId))
            },
            delegateCodeEditor: { [weak self] task in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.codeEditorDelegate.execute(
                    task: task,
                    workspaceId: self.activeWorkspaceId,
                    sessionId: self.activeSessionId
                )
            },
            openTaskSession: { [weak self] title, brief in
                self?.openTaskSession(title: title, brief: brief)
            },
            // Same directory Puck's executor writes to, so `id` joins the
            // agent's tool_call/tool_result with pet-app's exec lines in one
            // file (protocol section 7). Two processes appending to one file:
            // each line is a single small write, which append-mode keeps
            // whole -- interleaved order, never interleaved bytes.
            logger: ToolExecutionLogger()
        )
    }

    /// Every tool_result off the socket, so the dispatcher can match it to
    /// the call waiting for it.
    func handle(_ result: ToolResult) {
        dispatcher.handle(result)
    }

    /// The agent decided this turn is real work and wants it out of the
    /// casual session (protocol 3.4 `session_create(origin=agent)`,
    /// 04_ai-module.md 3.7). Two things happen, in this order:
    ///
    /// 1. The session is announced. Like every other event this app produces,
    ///    it is broadcast rather than applied locally -- pet-app relays
    ///    session_create to every gui connection including this one, so the
    ///    sidebar entry and the automatic switch to it come from the same
    ///    path a workspace-created session would take (ClientWindowStore
    ///    already handles origin=agent by following the user along).
    /// 2. Everything the rest of the run emits is re-addressed to it, which
    ///    is the whole point: a 10-minute code_editor delegation, its
    ///    progress, and its 중지 button all belong to the task session, and
    ///    the casual conversation stays usable while it runs.
    private func openTaskSession(title: String, brief: String) {
        let sessionId = UUID().uuidString
        let sourceSessionId = activeSessionId
        _ = broadcast(.sessionCreate(
            workspaceId: activeWorkspaceId,
            sessionId: sessionId,
            title: title,
            origin: .agent
        ))
        // The local half of the move -- the part the socket has no message
        // for. Carries the user's own message across and closes the chat it
        // was written in (see ClientWindowStore.moveTurnToTaskSession).
        onTaskSessionOpened?(activeWorkspaceId, sourceSessionId, sessionId, title, activeCommand)
        activeSessionId = sessionId
        if !brief.isEmpty {
            _ = broadcast(.event(.textChunk(text: brief), workspaceId: activeWorkspaceId, sessionId: sessionId))
        }
    }

    /// Every event off the socket. Only the delegate reads them, and only
    /// agent_done for a session it is waiting on -- the chat timeline and the
    /// pet's own reactions are fed elsewhere (AppDelegate.handle).
    func handle(_ event: BridgeEvent, sessionId: String) {
        codeEditorDelegate.handle(event, sessionId: sessionId)
    }

    /// pet-app went away: nothing in flight can be answered any more.
    func socketDisconnected() {
        dispatcher.failAllInFlight()
        codeEditorDelegate.failAllInFlight(detail: "pet-app과의 연결이 끊겼어요.")
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
        activeCommand = command
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
    /// a pending approval doesn't strand the loop forever. A delegated
    /// code_editor is stranded the same way (its 600s timeout is the only
    /// other way out), so 중지 has to release that too: workspace is told to
    /// abort the run it is doing on our behalf, and the tool call gives up
    /// without waiting to hear back.
    func cancelPendingApprovals() {
        lock.lock()
        let waiting = pendingApprovals
        pendingApprovals.removeAll()
        lock.unlock()
        for (_, continuation) in waiting { continuation.resume(returning: false) }

        _ = broadcast(.runCancel(sessionId: activeSessionId))
        codeEditorDelegate.failAllInFlight(error: "cancelled", detail: "사용자가 중지했어요.")
    }

    private func awaitApproval(id: String) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            pendingApprovals[id] = continuation
            lock.unlock()
        }
    }
}

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
    /// code_editor runs here as of 2026-08-15. It used to be delegated over
    /// user_input to workspace's own agent (CodeEditorDelegate, deleted); now
    /// this app spawns the ACP agent itself, so the tool completes without a
    /// second process being alive.
    private let codeEditorRunner: CodeEditorRunner
    private let resolveProjectPath: (String) -> String?
    /// What to tell the model about the workspace a run belongs to.
    private let describeWorkspace: (String) -> AgentRunner.WorkspaceContext?
    /// read_file/open_in_editor's implementation -- see EditorFileDelegate.
    private let editorFileDelegate: EditorFileDelegate
    private var runner: AgentRunner!

    /// approvalId -> the run waiting on the user's answer.
    private var pendingApprovals: [String: CheckedContinuation<Bool, Never>] = [:]
    /// The code_editor run the 중지 button would cancel, if any.
    private var activeCodeEditorRequestId: String?
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

    /// Set by AppDelegate: reveal the editor pane on this workspace's file.
    /// Called when the agent opens a file for the user to look at, and for
    /// every file a code_editor run touches: asking to be shown code should
    /// put it on screen, and watching one get written should follow along.
    var onRevealInEditor: ((_ workspaceId: String, _ path: String) -> Void)?

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

    init(
        broadcast: @escaping (BridgeMessage) -> Bool,
        resolveProjectPath: @escaping (String) -> String?,
        describeWorkspace: @escaping (String) -> AgentRunner.WorkspaceContext? = { _ in nil }
    ) {
        self.broadcast = broadcast
        self.describeWorkspace = describeWorkspace
        self.dispatcher = PetToolDispatcher(send: broadcast)
        self.resolveProjectPath = resolveProjectPath
        self.editorFileDelegate = EditorFileDelegate(resolveProjectPath: resolveProjectPath)

        // Declared before `runner` so the closures below can capture it; the
        // approval gate and event sink are attached afterwards, once `self`
        // exists to weakly capture.
        var relayEvent: ((BridgeEvent, String) -> Void)?
        var revealInEditor: ((String, String) -> Void)?
        var askPermission: ((AcpPermissionRequest) async -> Bool)?
        self.codeEditorRunner = CodeEditorRunner(
            environment: CodeEditorRunnerEnvironment(
                startAgent: { kind, projectPath in
                    let command = try AcpAgentCommandResolver.command(
                        for: kind,
                        scriptURL: AcpAgentCommandResolver.bundledScriptURL(for: kind),
                        node: AcpAgentCommandResolver.resolveNode(),
                        vendorCLI: AcpAgentCommandResolver.resolveVendorCLI(for: kind)
                    )
                    let process = AcpAgentProcess(
                        command: command,
                        projectPath: projectPath,
                        credentials: AgentConfiguration.load().codingAgentCredentials(for: kind)
                    )
                    try process.start()
                    return process
                },
                credentials: { AgentConfiguration.load().codingAgentCredentials(for: $0) },
                codingAgent: { AgentConfiguration.load().codingAgent }
            ),
            onUpdate: { requestId, workspaceId, update in
                // Follow the agent file by file while it works. The path comes
                // from ACP's own tool_call locations, which is also what makes
                // the pet jump to a new file, so the editor and the pet stay
                // on the same one.
                if let path = AcpEventMapping.editedPath(in: update) {
                    revealInEditor?(workspaceId, path)
                }
                guard let event = AcpEventMapping.event(for: update, callID: requestId) else { return }
                relayEvent?(event, workspaceId)
            },
            resolvePermission: { request in await askPermission?(request) ?? false }
        )
        self.runner = AgentRunner(
            client: makeAgentLLMClient({ .load() }),
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
                return await self.runCodeEditor(task: task)
            },
            openTaskSession: { [weak self] title, brief in
                self?.openTaskSession(title: title, brief: brief)
            },
            delegateReadFile: { [weak self] path in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.editorFileDelegate.readFile(path: path, workspaceId: self.activeWorkspaceId)
            },
            delegateOpenInEditor: { [weak self] path in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                let result = await self.editorFileDelegate.openInEditor(path: path, workspaceId: self.activeWorkspaceId)
                // Opening a tab in a pane nobody can see is not "showing" it.
                if result.ok { self.onRevealInEditor?(self.activeWorkspaceId, path) }
                return result
            },
            delegateListFiles: { [weak self] in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.editorFileDelegate.listFiles(workspaceId: self.activeWorkspaceId)
            },
            // Same directory Puck's executor writes to, so `id` joins the
            // agent's tool_call/tool_result with pet-app's exec lines in one
            // file (protocol section 7). Two processes appending to one file:
            // each line is a single small write, which append-mode keeps
            // whole -- interleaved order, never interleaved bytes.
            logger: ToolExecutionLogger()
        )

        // Now that `self` exists, close the two loops the runner was built
        // with placeholders for. Broadcast rather than applied locally, for
        // the reason this file's header gives.
        revealInEditor = { [weak self] workspaceId, path in
            guard let self else { return }
            Task { @MainActor in
                // Through the same delegate open_in_editor uses, so the tab
                // lands in the pane the user is looking at rather than a
                // second, disconnected store.
                _ = await self.editorFileDelegate.openInEditor(path: path, workspaceId: workspaceId)
                self.onRevealInEditor?(workspaceId, path)
            }
        }
        relayEvent = { [weak self] event, workspaceId in
            guard let self else { return }
            _ = self.broadcast(.event(event, workspaceId: workspaceId, sessionId: self.activeSessionId))
        }
        askPermission = { [weak self] request in
            guard let self else { return false }
            let approvalId = UUID().uuidString
            let summary = request.toolName.map { "코드 편집: \($0)" } ?? "코딩 에이전트가 승인을 요청했어요."
            _ = self.broadcast(.event(
                .awaitApproval(summary: summary, approvalId: approvalId),
                workspaceId: self.activeWorkspaceId,
                sessionId: self.activeSessionId
            ))
            return await self.awaitApproval(id: approvalId)
        }
    }

    /// One code_editor call. The workspace has to have a project directory --
    /// an agent with nowhere to edit is refused up front rather than started
    /// and left to fail on its first write.
    private func runCodeEditor(task: String) async -> DispatchedToolResult {
        let workspaceId = activeWorkspaceId
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(
                ok: false,
                data: nil,
                error: "execution_failed",
                detail: "이 워크스페이스에는 프로젝트 폴더가 없어서 코드를 편집할 수 없어요."
            )
        }
        let requestId = UUID().uuidString
        lock.lock(); activeCodeEditorRequestId = requestId; lock.unlock()
        defer {
            lock.lock()
            if activeCodeEditorRequestId == requestId { activeCodeEditorRequestId = nil }
            lock.unlock()
        }

        let result = await codeEditorRunner.run(
            requestId: requestId,
            workspaceId: workspaceId,
            projectPath: projectPath,
            task: task
        )
        // "cancelled"/"timeout" are protocol codes of their own; everything
        // else the runner reports is vocabulary the model has no entry for.
        let passThroughCodes: Set<String> = ["cancelled", "timeout"]
        return DispatchedToolResult(
            ok: result.ok,
            data: result.ok ? .string(result.summary) : nil,
            error: result.ok ? nil : (passThroughCodes.contains(result.error ?? "") ? result.error : "execution_failed"),
            detail: result.detail ?? result.summary
        )
    }

    /// The chat's 중지 button. Reaches the ACP agent through session/cancel
    /// rather than a run_cancel on the socket, now that the agent is ours.
    func cancelActiveCodeEditor() {
        lock.lock()
        let requestId = activeCodeEditorRequestId
        lock.unlock()
        guard let requestId else { return }
        Task { _ = await codeEditorRunner.cancel(requestId: requestId) }
    }

    /// The app is quitting. An ACP child is a node process plus its vendor
    /// binary, and nothing else reaps it: closing the chat window terminates
    /// this app, which would otherwise leave a code_editor run orphaned.
    func endCodeEditorAgents() {
        codeEditorRunner.terminateAll()
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

    /// Every event off the socket. Nothing here consumes them any more: the
    /// one reader was CodeEditorDelegate, waiting on workspace's agent_done to
    /// finish a delegated edit. code_editor completes in-process now, so the
    /// chat timeline and the pet's reactions (fed elsewhere, AppDelegate.handle)
    /// are the only consumers left. Kept as a no-op rather than removed so the
    /// socket plumbing that calls it stays unchanged.
    func handle(_ event: BridgeEvent, sessionId: String) {}

    /// pet-app went away: nothing in flight can be answered any more. Tool
    /// dispatch still crosses the socket, so it still has to be failed; the
    /// ACP agent does not, and keeps running.
    func socketDisconnected() {
        dispatcher.failAllInFlight()
    }

    func run(command: String, workspaceId: String, sessionId: String) {
        let configuration = configuration
        guard configuration.isConfigured else {
            // Said as a normal agent turn rather than an alert -- it belongs
            // in the transcript next to the message that couldn't be answered.
            // Names the actual paths that were searched rather than "check
            // your config" -- the search order is the answer to the question
            // this message provokes. Names the key variable the *selected*
            // provider reads, not always OpenAI's -- switching to Anthropic
            // in Settings and still being told to set OPENAI_API_KEY is the
            // exact confusion the provider picker exists to prevent.
            let searched = AgentConfiguration.defaultSearchPaths
                .map { $0.appendingPathComponent(".env").path }
                .joined(separator: "\n")
            let message = """
            \(configuration.provider.displayName) API 키가 없어요. 아래 중 한 곳의 .env에 \(configuration.provider.apiKeyEnvironmentVariable)=... 를 넣어주세요.
            \(searched)
            """
            _ = broadcast(.event(.textChunk(text: message), workspaceId: workspaceId, sessionId: sessionId))
            _ = broadcast(.event(.agentDone(ok: false, summary: message), workspaceId: workspaceId, sessionId: sessionId))
            return
        }

        activeWorkspaceId = workspaceId
        activeSessionId = sessionId
        activeCommand = command
        // Before the run, not at init: which workspace is active changes
        // between turns, and the runner only re-announces it when it differs.
        runner.workspaceContext = describeWorkspace(workspaceId)
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
    /// a pending approval doesn't strand the loop forever. A code_editor run
    /// is stranded the same way (its own timeout is the only other way out,
    /// and it is 600s long), so 중지 has to release that too: the ACP agent is
    /// told to stop through session/cancel and then signalled.
    func cancelPendingApprovals() {
        lock.lock()
        let waiting = pendingApprovals
        pendingApprovals.removeAll()
        lock.unlock()
        for (_, continuation) in waiting { continuation.resume(returning: false) }

        _ = broadcast(.runCancel(sessionId: activeSessionId))
        cancelActiveCodeEditor()
    }

    private func awaitApproval(id: String) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            pendingApprovals[id] = continuation
            lock.unlock()
        }
    }

}

//
//  CodeEditorRunner.swift
//  Puck
//
//  Runs code_editor: one queue per workspace, one ACP agent process per run.
//  Folds together workspace/src/agent-host/{index,code-editor-queue,
//  run-registry,run-cancellation}.ts -- four files that were separate because
//  a process boundary (Electron main <-> utility process) ran through the
//  middle of them. With that boundary gone, so is the reason to split.
//
//  Serial per workspace, parallel across workspaces: two agents editing the
//  same project at once would interleave writes to the same files, while two
//  different projects have nothing to contend over. Same rule the TS queue
//  enforced.
//

import Foundation

/// What the runner needs from the outside world, injected so tests can drive a
/// scripted agent instead of spawning node.
struct CodeEditorRunnerEnvironment {
    /// Builds the transport for one run. Returning nil means the agent cannot
    /// be started at all (no node, no codex CLI, missing bundle).
    var startAgent: (_ kind: CodingAgentKind, _ projectPath: String) throws -> AcpAgentTransport
    var credentials: (_ kind: CodingAgentKind) -> [String: String]
    var codingAgent: () -> CodingAgentKind
}

actor CodeEditorRunner {
    /// A run that is queued or in flight.
    private struct Run {
        let requestId: String
        let workspaceId: String
        var session: AcpCodeEditorSession?
        var process: AcpAgentTransport?
        var cancelled = false
    }

    private let environment: CodeEditorRunnerEnvironment
    private let onUpdate: (_ requestId: String, _ workspaceId: String, _ update: AcpSessionUpdate) -> Void
    private let resolvePermission: AcpPermissionResolver

    /// workspaceId -> the tail of that workspace's queue, so a new run can
    /// await its predecessor without a lock or a polling loop.
    private var queueTails: [String: Task<Void, Never>] = [:]
    private var runs: [String: Run] = [:]

    init(
        environment: CodeEditorRunnerEnvironment,
        onUpdate: @escaping (_ requestId: String, _ workspaceId: String, _ update: AcpSessionUpdate) -> Void = { _, _, _ in },
        resolvePermission: @escaping AcpPermissionResolver = { _ in false }
    ) {
        self.environment = environment
        self.onUpdate = onUpdate
        self.resolvePermission = resolvePermission
    }

    /// - Returns: the tool result. Never throws -- code_editor's caller is a
    ///   tool executor that has to report something back to the model.
    func run(
        requestId: String,
        workspaceId: String,
        projectPath: String,
        task: String
    ) async -> CodeEditorResult {
        guard runs[requestId] == nil else {
            return CodeEditorResult(
                ok: false, summary: "중복된 요청입니다.", changedFiles: [],
                error: "duplicate_request", detail: requestId
            )
        }
        runs[requestId] = Run(requestId: requestId, workspaceId: workspaceId)

        // The tail has to represent "this run's *work* is finished", not "this
        // run has been admitted". Chaining bare gates that only await their own
        // predecessor lets every run through at once: each gate completes as
        // soon as the one before it does, which is immediately.
        let predecessor = queueTails[workspaceId]
        let work = Task<CodeEditorResult, Never> { [weak self] in
            _ = await predecessor?.value
            guard let self else { return .cancelled() }
            return await self.executeIfStillWanted(
                requestId: requestId, workspaceId: workspaceId, projectPath: projectPath, task: task
            )
        }
        let tail = Task<Void, Never> { _ = await work.value }
        queueTails[workspaceId] = tail

        let result = await work.value
        runs.removeValue(forKey: requestId)
        // Only clear the tail if nobody queued behind us.
        if queueTails[workspaceId] == tail { queueTails.removeValue(forKey: workspaceId) }
        return result
    }

    /// The queue admitted this run; honour a cancel that arrived while it
    /// waited rather than spawning an agent for work nobody wants.
    private func executeIfStillWanted(
        requestId: String,
        workspaceId: String,
        projectPath: String,
        task: String
    ) async -> CodeEditorResult {
        if runs[requestId]?.cancelled == true { return .cancelled() }
        return await execute(requestId: requestId, workspaceId: workspaceId, projectPath: projectPath, task: task)
    }

    /// Idempotent, and safe before the run has started: a run cancelled while
    /// still queued never spawns an agent at all.
    func cancel(requestId: String) -> Bool {
        guard var run = runs[requestId] else { return false }
        run.cancelled = true
        runs[requestId] = run
        run.session?.cancel()
        if let process = run.process {
            // Give session/cancel a moment to land before falling back to
            // signals -- the TS adapter used the same two seconds.
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning { process.terminate() }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if process.isRunning { process.kill() }
            }
        }
        return true
    }

    func cancelAll() {
        for requestId in runs.keys { _ = cancel(requestId: requestId) }
    }

    // MARK: - Internals

    private func execute(
        requestId: String,
        workspaceId: String,
        projectPath: String,
        task: String
    ) async -> CodeEditorResult {
        let kind = environment.codingAgent()
        let tracker = ProjectChangeTracker(root: URL(fileURLWithPath: projectPath, isDirectory: true))
        tracker.start()

        let process: AcpAgentTransport
        do {
            process = try environment.startAgent(kind, projectPath)
        } catch {
            return CodeEditorResult(
                ok: false,
                summary: Self.unavailableSummary(for: error, kind: kind),
                changedFiles: tracker.finish(),
                error: "agent_unavailable",
                detail: String(describing: error)
            )
        }

        let session = AcpCodeEditorSession(
            connection: process.connection,
            projectPath: projectPath,
            onUpdate: { [onUpdate] update in onUpdate(requestId, workspaceId, update) },
            resolvePermission: resolvePermission
        )
        runs[requestId]?.session = session
        runs[requestId]?.process = process
        // A cancel that arrived while the agent was starting has to be honoured
        // here, or it would be lost between the queue check and the first await.
        if runs[requestId]?.cancelled == true {
            session.cancel()
            process.kill()
            return .cancelled(changedFiles: tracker.finish())
        }

        var result = await session.run(task: task)
        process.terminate()
        result.changedFiles = tracker.finish()
        return result
    }

    private static func unavailableSummary(for error: Error, kind: CodingAgentKind) -> String {
        switch error as? AcpAgentCommandError {
        case .nodeNotFound:
            return "코드 편집에는 Node.js가 필요합니다. 설치 후 다시 시도해 주세요."
        case .codexCLINotFound:
            return "codex CLI를 찾을 수 없습니다. 설치하거나 설정에서 claude를 선택해 주세요."
        case .agentScriptMissing:
            return "코딩 에이전트(\(kind.rawValue))가 앱에 포함되어 있지 않습니다."
        case .none:
            return "코딩 에이전트를 시작하지 못했습니다."
        }
    }
}

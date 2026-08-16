//
//  AcpCodeEditorSession.swift
//  Puck
//
//  One code_editor run: initialize -> session/new -> session/prompt, streaming
//  session/update along the way and answering session/request_permission.
//  The protocol half of workspace/src/agent-host/acp-adapter.ts.
//
//  Takes an AcpConnection rather than making one, so the whole turn can be
//  exercised against a scripted stream with no node process involved (see
//  AcpCodeEditorSessionTests).
//

import Foundation

struct CodeEditorResult: Equatable {
    var ok: Bool
    var summary: String
    var changedFiles: [String]
    var error: String?
    var detail: String?

    static func cancelled(changedFiles: [String] = []) -> CodeEditorResult {
        CodeEditorResult(ok: false, summary: "중단됨", changedFiles: changedFiles, error: "cancelled")
    }

    /// What the tool_result should carry as its `detail`.
    ///
    /// On a failure the summary is the half written for a person ("claude CLI를
    /// 찾을 수 없습니다…") and `detail` the half written for a machine
    /// (`vendorCLINotFound(...)`, a stderr tail). Reporting only `detail` --
    /// which is what `detail ?? summary` did, since `detail` is set on every
    /// failing path -- meant the model and the transcript never saw the
    /// sentence that explains what to do. Summary first so the first line is
    /// the readable one: that line is all a collapsed tool row shows.
    var reportedDetail: String? {
        guard !ok else { return detail }
        var lines: [String] = []
        for part in [summary, detail] {
            guard let part, !part.isEmpty, !lines.contains(part) else { continue }
            lines.append(part)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// How an approval request is answered. Returns nil to cancel.
typealias AcpPermissionResolver = (AcpPermissionRequest) async -> Bool

final class AcpCodeEditorSession {
    private let connection: AcpConnection
    private let projectPath: String
    private let onUpdate: (AcpSessionUpdate) -> Void
    private let resolvePermission: AcpPermissionResolver

    private let lock = NSLock()
    private var summary = ""
    /// Write-shaped locations the agent reported outside the project. Detection
    /// only -- see AcpEventMapping.writesOutside.
    private var writesOutsideProject: Set<String> = []
    private var sessionID: String?
    private var isCancelled = false

    init(
        connection: AcpConnection,
        projectPath: String,
        onUpdate: @escaping (AcpSessionUpdate) -> Void = { _ in },
        resolvePermission: @escaping AcpPermissionResolver = { _ in false }
    ) {
        self.connection = connection
        self.projectPath = projectPath
        self.onUpdate = onUpdate
        self.resolvePermission = resolvePermission

        connection.onNotification = { [weak self] method, params in
            guard method == AcpMethod.sessionUpdate else { return }
            self?.applyUpdate(AcpSessionUpdate(raw: params))
        }
        connection.onRequest = { [weak self] request in
            guard let self else { return }
            guard request.method == AcpMethod.sessionRequestPermission else {
                // An agent request we don't implement is answered rather than
                // ignored: an unanswered JSON-RPC request stalls the agent for
                // the whole 600s tool timeout.
                connection.respond(to: request.id, result: .object([:]))
                return
            }
            Task { await self.answerPermission(request) }
        }
    }

    /// Runs the turn to completion. Errors are returned as a failed
    /// CodeEditorResult rather than thrown -- every caller is a tool executor
    /// that has to report *something* back to the model.
    func run(task: String) async -> CodeEditorResult {
        do {
            _ = try await connection.request(
                method: AcpMethod.initialize,
                params: .object([
                    "protocolVersion": .number(Double(acpProtocolVersion)),
                    "clientCapabilities": .object([:]),
                ])
            )

            let created = try await connection.request(
                method: AcpMethod.sessionNew,
                params: .object([
                    "cwd": .string(projectPath),
                    "mcpServers": .array([]),
                ])
            )
            guard let sessionID = created["sessionId"]?.stringValue else {
                return CodeEditorResult(
                    ok: false,
                    summary: "ACP 작업에 실패했습니다.",
                    changedFiles: [],
                    error: "acp_error",
                    detail: "session/new did not return a sessionId"
                )
            }
            lock.lock(); self.sessionID = sessionID; lock.unlock()

            if currentlyCancelled() {
                cancel()
                return .cancelled()
            }

            let finished = try await connection.request(
                method: AcpMethod.sessionPrompt,
                params: .object([
                    "sessionId": .string(sessionID),
                    "prompt": .array([.object(["type": .string("text"), "text": .string(task)])]),
                ])
            )

            if currentlyCancelled() { return .cancelled() }

            let stopReason = finished["stopReason"]?.stringValue ?? AcpStopReason.endTurn.rawValue
            if stopReason == AcpStopReason.cancelled.rawValue { return .cancelled() }
            let text = currentSummary().trimmingCharacters(in: .whitespacesAndNewlines)
            let escaped = currentWritesOutsideProject()
            guard escaped.isEmpty else {
                // Reported as a failure rather than a footnote on a success:
                // the run wrote where it was not asked to, and the user has to
                // know which paths to go look at.
                return CodeEditorResult(
                    ok: false,
                    summary: "이 작업이 프로젝트 밖의 파일을 수정했다고 보고했어요. 확인이 필요합니다.",
                    changedFiles: [],
                    error: "wrote_outside_project",
                    detail: escaped.sorted().joined(separator: "\n")
                )
            }
            return CodeEditorResult(
                ok: true,
                summary: text.isEmpty ? "ACP 작업 완료 (\(stopReason))" : text,
                changedFiles: []
            )
        } catch {
            if currentlyCancelled() { return .cancelled() }
            return CodeEditorResult(
                ok: false,
                summary: "ACP 작업에 실패했습니다.",
                changedFiles: [],
                error: "acp_error",
                detail: Self.detail(from: error)
            )
        }
    }

    /// Asks the agent to stop. Idempotent -- cancelling twice, or cancelling
    /// before session/new has returned, both do the right thing (the run()
    /// path re-checks after each await).
    func cancel() {
        lock.lock()
        isCancelled = true
        let sessionID = self.sessionID
        lock.unlock()
        guard let sessionID else { return }
        connection.notify(
            method: AcpMethod.sessionCancel,
            params: .object(["sessionId": .string(sessionID)])
        )
    }

    // MARK: - Internals

    private func applyUpdate(_ update: AcpSessionUpdate) {
        lock.lock()
        if !update.text.isEmpty { summary += update.text }
        for path in AcpEventMapping.writesOutside(root: projectPath, in: update) {
            writesOutsideProject.insert(path)
        }
        lock.unlock()
        onUpdate(update)
    }

    private func answerPermission(_ request: AcpConnection.IncomingRequest) async {
        let permission = AcpPermissionRequest(raw: request.params)
        // A cancelled run must not put an approval prompt in front of the
        // user for work that is already being abandoned.
        let approved = currentlyCancelled() ? false : await resolvePermission(permission)
        if approved, let option = permission.allowOption() {
            connection.respond(to: request.id, result: AcpPermissionRequest.outcome(selecting: option.id))
        } else if !approved, let option = permission.rejectOption() {
            connection.respond(to: request.id, result: AcpPermissionRequest.outcome(selecting: option.id))
        } else {
            connection.respond(to: request.id, result: AcpPermissionRequest.cancelledOutcome())
        }
    }

    private func currentlyCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isCancelled
    }

    private func currentSummary() -> String {
        lock.lock(); defer { lock.unlock() }
        return summary
    }

    private func currentWritesOutsideProject() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return writesOutsideProject
    }

    private static func detail(from error: Error) -> String {
        switch error {
        case AcpError.agent(let code, let message): return "ACP error \(code): \(message)"
        case AcpError.processExited(let detail): return detail.isEmpty ? "ACP 프로세스가 종료되었습니다." : detail
        default: return String(describing: error)
        }
    }
}

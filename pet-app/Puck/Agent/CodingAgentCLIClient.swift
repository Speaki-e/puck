//
//  CodingAgentCLIClient.swift
//  Puck
//
//  An AgentLLMClient backed by the vendor coding-agent CLI the user is already
//  logged into -- `claude` or `codex`, driven over ACP, the same child process
//  `code_editor` spawns. The point is the credential: this path needs no API
//  key at all, so the pet answers ordinary conversation on a machine that only
//  ever logged into a CLI.
//
//  ## It has no tools, and says so
//
//  `AgentLLMClient.send` hands over Puck's tool specs, but ACP has no
//  tool-call channel back to the host: the CLI runs its own tools inside its
//  own process and returns prose. So every turn from here is text-only, and
//  the prompt this builds *tells the model that*, overriding the tool
//  instructions in AgentRunner's system prompt. A model left believing it can
//  call `point_at` would narrate having pointed at something while the pet
//  stood still, which is the one failure mode worth spending a paragraph of
//  prompt on.
//
//  ## One process per turn
//
//  A conversation could instead keep one ACP session alive and send only the
//  newest message, which is what the CLI's own session model wants. It is not
//  what this does, for two reasons. `send` is handed the entire message array
//  every turn and has no session identity to key a long-lived child on -- the
//  runner owns the history, and a second copy of it inside the CLI could
//  disagree with the first. And an idle ACP child is a node process plus the
//  vendor's ~256MB native binary sitting there between turns; a chat that is
//  mostly idle would pay that continuously. So the whole transcript is
//  re-sent, the child lives exactly as long as the turn, and it is torn down
//  on every exit path.
//

import Foundation

enum CodingAgentCLIError: LocalizedError, Equatable {
    /// The agent could not be started -- no node, no CLI, missing bundle. The
    /// string is already the sentence to show (AcpAgentCommandError.summary).
    case unavailable(String)
    /// The turn started and then failed. Carries the ACP error plus whatever
    /// the CLI wrote to stderr, which is usually the only real explanation.
    case failed(String)
    case timedOut(seconds: Int)
    /// The turn ended cleanly but said nothing at all.
    case emptyReply(stopReason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let summary): return summary
        case .failed(let detail): return "코딩 CLI 오류: \(detail)"
        case .timedOut(let seconds): return "코딩 CLI가 \(seconds)초 안에 답하지 않아 중단했어요."
        case .emptyReply(let stopReason): return "코딩 CLI가 답을 주지 않았어요. (\(stopReason))"
        case .cancelled: return "중지했어요."
        }
    }
}

final class CodingAgentCLIClient: AgentLLMClient {
    /// Read per turn, not captured once: the CLI choice can change in Settings
    /// while the app is running, same as the key field.
    private let configuration: () -> AgentConfiguration
    /// Spawns the agent. Injected so a turn can be driven against a scripted
    /// stream with no node process involved.
    private let startAgent: (_ kind: CodingAgentKind, _ cwd: String) throws -> AcpAgentTransport
    /// Where `session/new` opens the agent. The active workspace's project when
    /// there is one -- a CLI asked about "this file" can then actually look --
    /// falling back to the home directory for a chat-only workspace.
    private let workingDirectory: () -> String
    private let timeoutSeconds: TimeInterval

    /// Long enough for a real answer on a cold CLI start (the vendor binary is
    /// ~256MB and the first turn pays for loading it), short enough that a
    /// wedged child does not hold the chat until the app is quit.
    static let defaultTimeoutSeconds: TimeInterval = 180

    init(
        configuration: @escaping () -> AgentConfiguration,
        workingDirectory: @escaping () -> String = { NSHomeDirectory() },
        timeoutSeconds: TimeInterval = CodingAgentCLIClient.defaultTimeoutSeconds,
        startAgent: @escaping (_ kind: CodingAgentKind, _ cwd: String) throws -> AcpAgentTransport
            = CodingAgentCLIClient.spawn
    ) {
        self.configuration = configuration
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.startAgent = startAgent
    }

    /// The real spawn, identical to the one `code_editor` uses -- same command
    /// resolution, same trimmed child environment, same credential forwarding.
    static func spawn(kind: CodingAgentKind, cwd: String) throws -> AcpAgentTransport {
        let command = try AcpAgentCommandResolver.command(
            for: kind,
            scriptURL: AcpAgentCommandResolver.bundledScriptURL(for: kind),
            node: AcpAgentCommandResolver.resolveNode(),
            vendorCLI: AcpAgentCommandResolver.resolveVendorCLI(for: kind)
        )
        let process = AcpAgentProcess(
            command: command,
            projectPath: cwd,
            credentials: AgentConfiguration.load().codingAgentCredentials(for: kind)
        )
        try process.start()
        return process
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        let kind = configuration().codingAgent
        let cwd = workingDirectory()

        let process: AcpAgentTransport
        do {
            process = try startAgent(kind, cwd)
        } catch {
            guard let error = error as? AcpAgentCommandError else {
                throw CodingAgentCLIError.unavailable(AcpAgentCommandError.unknownStartFailureSummary)
            }
            // A `codex` that is not installed has to fail here, plainly and
            // immediately, rather than hang: nothing was spawned, so there is
            // nothing to wait on.
            throw CodingAgentCLIError.unavailable(error.summary(purpose: "대화", kind: kind))
        }

        let session = AcpTurnSession(
            connection: process.connection,
            cwd: cwd,
            stderrTail: { [weak process] in process?.currentStderrTail() ?? "" }
        )
        let prompt = Self.prompt(for: messages)

        guard let outcome = await withDeadline(
            seconds: timeoutSeconds,
            work: { await session.run(prompt: prompt) }
        ) else {
            session.cancel()
            Self.shutDown(process)
            throw CodingAgentCLIError.timedOut(seconds: Int(timeoutSeconds))
        }
        Self.shutDown(process)

        switch outcome {
        case .cancelled:
            throw CodingAgentCLIError.cancelled
        case .failed(let failure):
            throw CodingAgentCLIError.failed(failure.text)
        case .completed(let completion):
            guard !completion.text.isEmpty else {
                throw CodingAgentCLIError.emptyReply(stopReason: completion.stopReason)
            }
            // Text only. The host's tools were offered and are not usable
            // here; `prompt` says so rather than leaving the model to discover
            // it by having a call ignored.
            _ = tools
            return GPTTurn(text: completion.text, toolCalls: [])
        }
    }

    /// SIGTERM, a moment, then SIGKILL -- `terminate()` alone is a request,
    /// and the transport is released as soon as this returns, so nothing would
    /// be left to escalate afterwards. Detached because the turn's answer is
    /// already in hand and must not wait on a child's exit.
    private static func shutDown(_ process: AcpAgentTransport) {
        Task {
            if process.isRunning { process.terminate() }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if process.isRunning { process.kill() }
        }
    }

    // MARK: - Prompt

    /// The whole conversation as one prompt, because a turn gets one.
    ///
    /// System messages first (AgentRunner's own prompt, plus the per-run
    /// workspace line), then the tool-availability override that corrects
    /// them, then the transcript. The override comes after the prompt it
    /// contradicts on purpose: the later instruction is the one models follow.
    static func prompt(for messages: [GPTMessage]) -> String {
        var systemLines: [String] = []
        var transcript: [String] = []

        for message in messages {
            switch message {
            case .system(let text):
                systemLines.append(text)
            case .user(let text):
                transcript.append("User: \(text)")
            case .assistant(let text, let toolCalls):
                if let text, !text.isEmpty { transcript.append("Assistant: \(text)") }
                // Turns taken under another provider can carry real tool
                // calls. Rendered as history rather than dropped, so a
                // conversation that switches providers mid-way still reads.
                for call in toolCalls {
                    transcript.append("Assistant (tool \(call.name)): \(call.argumentsJSON)")
                }
            case .tool(_, let content):
                transcript.append("Tool result: \(content)")
            }
        }

        var parts = systemLines
        parts.append(toolAvailabilityOverride)
        parts.append("Conversation so far:\n" + transcript.joined(separator: "\n"))
        parts.append("Reply to the last User message. Output only your reply.")
        return parts.joined(separator: "\n\n")
    }

    /// Corrects the host system prompt for this provider. Internal so a test
    /// can assert it is actually in the prompt -- the honesty of this path
    /// rests entirely on it being there.
    static let toolAvailabilityOverride = """
    IMPORTANT -- TOOL AVAILABILITY ON THIS CONNECTION:
    You are running through a coding-agent CLI, and the host application's tools are NOT connected \
    to you on this turn. You cannot launch apps, point the pet at anything, click, run shell \
    commands on the user's behalf, read or open files in the editor pane, open a task session, or \
    hand work to code_editor. Any such tool named above is unavailable right now; ignore those \
    instructions.
    So: answer in words only. Never say or imply that you launched, opened, pointed at, clicked, \
    edited, or ran anything -- you did not. If the user asks for an action that needs those tools, \
    say plainly that this provider can only talk, and that they can switch the AI 공급자 setting \
    to OpenAI or Anthropic to let the pet act. Everything else -- questions, explanations, \
    ordinary conversation -- answer normally.
    """
}

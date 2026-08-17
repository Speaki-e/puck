//
//  AgentRunner.swift
//  Puck
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  The tool-use loop -- plan/04_ai-module.md section 3.2, in Swift.
//
//  "날씨 앱 켜줘" reaches here as `run`, the model answers with launch_app,
//  PetToolDispatcher puts that on bridge.sock, pet-app launches it and walks
//  the pet over.
//
//  ## Where this deviates from the plan, and why
//
//  plan/04_ai-module.md puts this loop in `ai-module` -- a TypeScript module
//  on the Claude API, injected into `workspace` (Electron). Three things
//  about that are no longer true on the ground: workspace and ai-module are
//  both empty repos, the chat client became a Swift app, and the key the team
//  has is OpenAI's. Rewriting the loop in TS later is a real possibility, so
//  everything that *is* contract is kept where the plan put it -- the tool
//  registry in protocol, the wire format in BridgeMessages, approval before
//  dispatch -- and only the loop itself is local. What a TS port would have
//  to redo is this file and GPTClient, not the contract around them.
//
//  ## Events are the output, not a side effect
//
//  Every step emits a BridgeEvent. The client applies them to the chat
//  timeline and broadcasts them to pet-app, which is what makes the pet think,
//  point, and celebrate -- ChatSession.apply and EventRouter.reaction already
//  handle the full set, so producing them is all the integration there is.
//

import Foundation

/// Emitted for every step of a run. The host decides what to do with them
/// (render, broadcast, log) -- the runner never touches UI or the socket.
typealias AgentEventSink = (BridgeEvent) -> Void

/// Asks the user to approve a dangerous tool. Returns whether to proceed.
typealias AgentApprovalGate = (_ summary: String, _ approvalId: String) async -> Bool

/// Hands a coding task to workspace's agent and returns what it reported.
/// See CodeEditorDelegate for why this is a closure and not another entry in
/// PetToolDispatcher.
typealias AgentCodeEditorDelegation = (_ task: String) async -> DispatchedToolResult

/// Reads or opens a file in the client window's native editor pane. Not
/// dispatched via PetToolDispatcher either, for the same reason as
/// code_editor: both need the current run's workspaceId to resolve a
/// relative path against a specific project root, which a tool_dispatch's
/// bare `{path}` argument has no room for, and which pet-app's
/// process-wide ToolExecutor (Puck.app, not this app) has no way to reach
/// PuckClient's own editor-pane state to answer anyway.
typealias AgentFileDelegation = (_ path: String) async -> DispatchedToolResult

/// Lists the active workspace's project files. Takes no path -- which project
/// is a property of the run, not something the model chooses.
typealias AgentFileListing = () async -> DispatchedToolResult

/// Branches the casual conversation into its own task session; everything the
/// run emits after this is addressed to the new one.
typealias AgentTaskSessionOpener = (_ title: String, _ brief: String) -> Void

final class AgentRunner {
    private let client: any AgentLLMClient
    private let dispatcher: PetToolDispatcher
    private let approve: AgentApprovalGate
    private let emit: AgentEventSink
    /// nil in the standalone case (no workspace to delegate to), and then
    /// code_editor is not offered to the model at all -- the same rule the
    /// pet-app-only tool list was already built on.
    private let delegateCodeEditor: AgentCodeEditorDelegation?
    /// Offered only alongside code_editor: with nowhere to delegate to, there
    /// is no long-running work to move out of the casual session, and a task
    /// session that only ever holds chat is just a confusing empty room.
    private let openTaskSession: AgentTaskSessionOpener?
    /// nil only in the standalone case (same rule as delegateCodeEditor) --
    /// unlike code_editor, these two don't depend on a workspace/ACP process
    /// being connected, only on the active workspace having a project bound.
    private let delegateReadFile: AgentFileDelegation?
    private let delegateOpenInEditor: AgentFileDelegation?
    /// Offered whenever read_file is: both answer from the same project root,
    /// and a model that can read a file but not find one is the situation this
    /// was added to fix.
    private let delegateListFiles: AgentFileListing?
    /// protocol section 7's `src: "agent"` lines. Without them a failed call
    /// is an opaque uuid in pet-app's log with no tool name and no reason.
    private let logger: ToolExecutionLogging?
    private let toolSpecs: [GPTToolSpec]

    /// Conversation memory for the session. Per plan/04_ai-module.md 3.4 this
    /// is in-memory only -- persistence is explicitly後순위.
    private var messages: [GPTMessage] = []

    /// A model that keeps calling tools without concluding would otherwise
    /// loop until the API bill says stop. Ten is well past any sequence the
    /// case table describes (the longest is launch → find → point).
    private static let maxTurns = 10

    init(
        client: any AgentLLMClient,
        dispatcher: PetToolDispatcher,
        approve: @escaping AgentApprovalGate,
        emit: @escaping AgentEventSink,
        delegateCodeEditor: AgentCodeEditorDelegation? = nil,
        openTaskSession: AgentTaskSessionOpener? = nil,
        delegateReadFile: AgentFileDelegation? = nil,
        delegateOpenInEditor: AgentFileDelegation? = nil,
        delegateListFiles: AgentFileListing? = nil,
        logger: ToolExecutionLogging? = nil
    ) {
        self.logger = logger
        self.client = client
        self.dispatcher = dispatcher
        self.approve = approve
        self.emit = emit
        self.delegateCodeEditor = delegateCodeEditor
        self.openTaskSession = delegateCodeEditor == nil ? nil : openTaskSession
        self.delegateReadFile = delegateReadFile
        self.delegateOpenInEditor = delegateOpenInEditor
        self.delegateListFiles = delegateListFiles
        toolSpecs = Self.petToolSpecs
            + (delegateCodeEditor == nil ? [] : [Self.codeEditorSpec])
            + (self.openTaskSession == nil ? [] : [Self.openTaskSessionSpec])
            + (delegateReadFile == nil ? [] : [Self.readFileSpec])
            + (delegateOpenInEditor == nil ? [] : [Self.openInEditorSpec])
            + (delegateListFiles == nil ? [] : [Self.listFilesSpec])
        messages = [.system(Self.systemPrompt)]
    }

    /// Drops everything but the system prompt -- a new chat session should not
    /// inherit the last one's context.
    func reset() {
        messages = [.system(Self.systemPrompt)]
        announcedWorkspaceContext = nil
    }

    /// Describes the workspace this run belongs to. Injected per run rather
    /// than baked into the system prompt: the user can switch workspaces
    /// between turns, and a prompt built at init would keep naming the first
    /// one forever.
    ///
    /// Without it the model had no idea a project was open at all. Asked to
    /// analyze "this directory" it reached for get_frontmost_window -- the
    /// only tool whose name sounded spatial -- got a window title back, and
    /// correctly concluded it had nothing to answer with.
    struct WorkspaceContext: Equatable {
        let name: String
        /// nil for a chat-only workspace.
        let projectPath: String?

        var promptLine: String {
            guard let projectPath else {
                return "Current workspace: \(name). No project folder is bound to it, so there are no files to read or list."
            }
            return "Current workspace: \(name), bound to the project at \(projectPath). "
                + "\"this project\" / \"this directory\" / \"여기\" mean that folder. "
                + "Paths you pass to file tools are relative to it."
        }
    }

    /// Set by the host before each run. Kept as a property rather than a `run`
    /// parameter so the many existing call sites and tests stay untouched.
    var workspaceContext: WorkspaceContext?

    /// What was last announced to the model, so a ten-turn conversation in one
    /// workspace does not accumulate ten identical system lines.
    private var announcedWorkspaceContext: WorkspaceContext?

    /// What the transcript ends with when the user presses 중지. Not an error
    /// string: a stop the user asked for is an outcome, not a failure, so it
    /// never goes through the `catch` path that reports a reason.
    static let cancelledSummary = "중지했어요."

    func run(command: String) async {
        if let workspaceContext, workspaceContext != announcedWorkspaceContext {
            messages.append(.system(workspaceContext.promptLine))
            announcedWorkspaceContext = workspaceContext
        }
        messages.append(.user(command))
        emit(.agentThinking)

        for _ in 0..<Self.maxTurns {
            if Task.isCancelled {
                emitCancelled()
                return
            }
            let turn: GPTTurn
            do {
                turn = try await client.send(messages: messages, tools: toolSpecs)
            } catch {
                // Checked before the error is described: a cancelled
                // `URLSession.data(for:)` surfaces as URLError(.cancelled)
                // rather than CancellationError, and reporting either one as
                // "요청이 취소되었습니다" would make the 중지 button look like a
                // network failure.
                if Task.isCancelled {
                    emitCancelled()
                    return
                }
                // The raw description -- which for GPTError.http carries the
                // provider's whole response body -- goes to the log, and only
                // there. Once. `agent_done(ok: false)` is the row that already
                // renders a failure (DoneRow's ✗), so emitting a text_chunk
                // too put the identical text in an assistant bubble directly
                // above it.
                AppLogger.shared.log(.error, "agent run failed: \(Self.rawFailureDescription(for: error))")
                emit(.agentDone(ok: false, summary: Self.failureSummary(for: error)))
                return
            }

            if let text = turn.text, !text.isEmpty {
                emit(.textChunk(text: text))
            }

            guard !turn.toolCalls.isEmpty else {
                // No tools asked for: the model is answering, so the run ends
                // here. Its own text is the summary.
                messages.append(.assistant(text: turn.text, toolCalls: []))
                emit(.agentDone(ok: true, summary: turn.text ?? ""))
                return
            }

            messages.append(.assistant(text: turn.text, toolCalls: turn.toolCalls))
            for call in turn.toolCalls {
                // Between calls, not only between turns: a turn can ask for
                // several tools, and a stop pressed during the first one
                // should not still run the rest.
                if Task.isCancelled {
                    emitCancelled()
                    return
                }
                await perform(call)
            }
        }

        let hitCeiling = "도구를 \(Self.maxTurns)번 넘게 호출해서 중단했어요."
        emit(.textChunk(text: hitCeiling))
        emit(.agentDone(ok: false, summary: hitCeiling))
    }

    /// The one exit a cancelled run takes. Emits `agent_done` like every other
    /// ending does, so the session leaves its running state instead of holding
    /// a spinner forever; `ok: false` because the turn did not finish what it
    /// was asked, and EventRouter deliberately gives a failed run no reaction
    /// (a "task_success" jump for a stop would be worse than none).
    private func emitCancelled() {
        emit(.textChunk(text: Self.cancelledSummary))
        emit(.agentDone(ok: false, summary: Self.cancelledSummary))
    }

    // MARK: - Failure reporting

    /// The one line a failed run leaves in the transcript.
    ///
    /// `GPTError.errorDescription` inlines the provider's response body on
    /// purpose -- it is the debugging text, and it is what goes to the log --
    /// but a bad key made that ~20 lines of OpenAI's JSON in the chat for what
    /// is really "your key is wrong". This maps the statuses that mean
    /// something the user can act on to a sentence saying what to do, and
    /// leaves every other kind of failure its own words rather than collapsing
    /// the lot into one generic apology.
    ///
    /// Provider-neutral, like `GPTError` itself: the same path serves
    /// Anthropic, and whoever reads this already knows which provider is
    /// selected.
    static func failureSummary(for error: Error) -> String {
        switch error {
        case GPTError.notConfigured:
            return "API 키가 없어요. \(settingsHint)"
        case GPTError.http(let status, let body):
            return httpFailureSummary(status: status, body: body)
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Everything the error knew, for the log.
    static func rawFailureDescription(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// ⌘, opens 설정 in both apps (ClientMainMenu binds it), so naming the
    /// shortcut is a real instruction and not decoration.
    private static let settingsHint = "설정(⌘,)에서 키를 확인해 주세요."

    private static func httpFailureSummary(status: Int, body: String) -> String {
        switch status {
        case 401, 403:
            return "API 키가 올바르지 않아요. \(settingsHint)"
        case 404:
            // What a wrong model name returns; a missing endpoint would be our
            // bug, and then the log is where to look anyway.
            return "모델을 찾을 수 없어요. 설정(⌘,)에서 모델 이름을 확인해 주세요."
        case 429:
            return "요청이 너무 잦거나 사용 한도를 넘었어요. 잠시 후 다시 시도해 주세요."
        case 500...599:
            return "AI 서버가 응답하지 못했어요 (오류 \(status)). 잠시 후 다시 시도해 주세요."
        default:
            // Anything else keeps the provider's own reason -- a bare status
            // does not say what to change -- but one sentence of it, not the
            // envelope it arrived in.
            guard let message = providerMessage(in: body) else { return "API 오류 \(status)가 났어요." }
            return "API 오류 \(status): \(message)"
        }
    }

    /// `{"error": {"message": ...}}` -- the shape both providers use. Returns
    /// nil for a body that isn't that, rather than guessing: a truncated slice
    /// of unknown JSON is the noise this exists to remove.
    private static func providerMessage(in body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return nil }
        // A DoneRow is one caption line; a provider that answers with a
        // paragraph gets the head of it, and the log keeps the rest.
        return firstLine.count <= 160 ? firstLine : String(firstLine.prefix(160)) + "…"
    }

    private func perform(_ call: GPTToolCall) async {
        let arguments = JSONValue.decodeObject(from: call.argumentsJSON)

        // The one tool that never crosses the socket and never shows up as a
        // tool call in the transcript: it only moves where the rest of this
        // run is addressed (01_protocol.md section 4, 04_ai-module.md 3.7 --
        // "결과는 onSessionCreated 콜백 → session_create 이벤트로만 통지").
        // Emitting tool_call/tool_result for it would put plumbing in the
        // chat and make the pet react to a session switch as if it were work.
        if call.name == Self.openTaskSessionToolName, let openTaskSession {
            guard
                case .object(let args) = arguments,
                case .string(let title)? = args["title"], !title.isEmpty
            else {
                messages.append(.tool(callId: call.id, content: "error: execution_failed -- title이 비어 있어요."))
                return
            }
            let brief = if case .string(let value)? = args["brief"] { value } else { "" }
            openTaskSession(title, brief)
            messages.append(.tool(callId: call.id, content: "ok -- 새 작업 세션 \"\(title)\"으로 옮겼습니다."))
            return
        }

        emit(.toolCall(id: call.id, tool: call.name, args: arguments, detail: nil))
        logger?.log(.agentToolCall(id: call.id, tool: call.name, args: arguments))

        if ToolRegistry.tool(named: call.name)?.requiresApproval == true {
            let summary = Self.approvalSummary(tool: call.name, arguments: call.argumentsJSON)
            emit(.awaitApproval(summary: summary, approvalId: call.id))
            guard await approve(summary, call.id) else {
                // Refusal is the model's to hear about, not an error to abort
                // on -- it should say so and offer something else. The code
                // never crosses the socket (docs/socket.md).
                report(callId: call.id, ok: false, error: "denied_by_user", detail: nil, data: nil)
                return
            }
        }

        let result: DispatchedToolResult
        if call.name == Self.codeEditorToolName, let delegateCodeEditor {
            // workspace's tool, so it never goes to PetToolDispatcher (which
            // would put a tool_dispatch pet-app can't execute on the socket).
            // project_path is deliberately dropped: workspace resolves the
            // path from the session's own workspace record and ignores what
            // the model sends, so passing it on would only invite the model
            // to think it decides.
            guard case .object(let args) = arguments, case .string(let task)? = args["task"], !task.isEmpty else {
                report(callId: call.id, ok: false, error: "execution_failed", detail: "task가 비어 있어요.", data: nil)
                return
            }
            result = await delegateCodeEditor(task)
        } else if call.name == Self.readFileToolName, let delegateReadFile {
            guard let path = Self.pathArgument(from: arguments) else {
                report(callId: call.id, ok: false, error: "execution_failed", detail: "path가 비어 있어요.", data: nil)
                return
            }
            result = await delegateReadFile(path)
        } else if call.name == Self.openInEditorToolName, let delegateOpenInEditor {
            guard let path = Self.pathArgument(from: arguments) else {
                report(callId: call.id, ok: false, error: "execution_failed", detail: "path가 비어 있어요.", data: nil)
                return
            }
            result = await delegateOpenInEditor(path)
        } else if call.name == Self.listFilesToolName, let delegateListFiles {
            // No arguments to validate: which project is a property of the
            // run, not something the model picks.
            result = await delegateListFiles()
        } else {
            result = await dispatcher.execute(tool: call.name, arguments: arguments)
        }
        report(callId: call.id, ok: result.ok, error: result.error, detail: result.detail, data: result.data)
    }

    /// One place for "tell the model, tell the UI, tell the pet" so a tool
    /// result can never reach one of the three and not the others.
    private func report(callId: String, ok: Bool, error: String?, detail: String?, data: JSONValue?) {
        // error is the model-facing vocabulary (may be "denied_by_user", which
        // never crosses the socket -- see ToolErrorCode's doc comment), so the
        // wire event only carries it when it's actually one of the closed
        // protocol codes.
        emit(.toolResult(id: callId, ok: ok, data: data, error: error.flatMap(ToolErrorCode.init(rawValue:)), detail: detail))
        // detail rides along in the error field when there is one: the code
        // alone ("execution_failed") is never enough to act on, and this line
        // is the only place the reason survives after the chat scrolls away.
        let reason = [error, detail].compactMap { $0 }.joined(separator: " -- ")
        logger?.log(.agentToolResult(id: callId, ok: ok, error: reason.isEmpty ? nil : reason))
        messages.append(.tool(callId: callId, content: Self.toolResultText(ok: ok, data: data, error: error, detail: detail)))
    }

    /// What the model actually reads back. Errors keep their protocol code so
    /// the model can distinguish "not connected" from "you asked for a tool
    /// that doesn't exist" and say something useful about it
    /// (plan/04_ai-module.md 3.2).
    private static func toolResultText(ok: Bool, data: JSONValue?, error: String?, detail: String?) -> String {
        if ok {
            guard let data, let encoded = data.jsonText else { return "ok" }
            return encoded
        }
        return ["error: \(error ?? "execution_failed")", detail].compactMap { $0 }.joined(separator: " -- ")
    }

    private static func approvalSummary(tool: String, arguments: String) -> String {
        switch tool {
        case "run_shell": return "셸 명령 실행: \(arguments)"
        case "run_applescript": return "AppleScript 실행: \(arguments)"
        case "click_element": return "화면 클릭: \(arguments)"
        default: return "\(tool) 실행: \(arguments)"
        }
    }

    /// Shared by read_file/open_in_editor -- both take just {path: string}.
    /// Internal, not private: directly unit-tested (see AgentRunnerTests).
    static func pathArgument(from arguments: JSONValue) -> String? {
        guard case .object(let args) = arguments, case .string(let path)? = args["path"], !path.isEmpty else {
            return nil
        }
        return path
    }

    // MARK: - Prompt and tool descriptions

    /// pet-app's own tools -- the ones PetToolDispatcher can actually put on
    /// the socket.
    private static let petToolSpecs: [GPTToolSpec] = ToolRegistry.tools(for: .petApp).map { tool in
        GPTToolSpec(name: tool.name, description: description(for: tool.name), parameters: tool.parameters)
    }

    static let codeEditorToolName = "code_editor"
    static let openTaskSessionToolName = "open_task_session"
    static let readFileToolName = "read_file"
    static let openInEditorToolName = "open_in_editor"

    private static let openTaskSessionSpec: GPTToolSpec = GPTToolSpec(
        name: openTaskSessionToolName,
        description: description(for: openTaskSessionToolName),
        parameters: ToolRegistry.tool(named: openTaskSessionToolName)?.parameters ?? []
    )

    /// The one workspace-owned tool that does have someone to run it, once a
    /// workspace is connected -- delegated rather than dispatched (see
    /// CodeEditorDelegate). Parameters come from the registry like every
    /// other tool, so the shape stays the contract's.
    private static let codeEditorSpec: GPTToolSpec = {
        let tool = ToolRegistry.tool(named: codeEditorToolName)
        return GPTToolSpec(
            name: codeEditorToolName,
            description: description(for: codeEditorToolName),
            parameters: tool?.parameters ?? []
        )
    }()

    private static let readFileSpec: GPTToolSpec = GPTToolSpec(
        name: readFileToolName,
        description: description(for: readFileToolName),
        parameters: ToolRegistry.tool(named: readFileToolName)?.parameters ?? []
    )

    static let listFilesToolName = "list_files"

    private static let listFilesSpec: GPTToolSpec = GPTToolSpec(
        name: listFilesToolName,
        description: description(for: listFilesToolName),
        parameters: ToolRegistry.tool(named: listFilesToolName)?.parameters ?? []
    )

    private static let openInEditorSpec: GPTToolSpec = GPTToolSpec(
        name: openInEditorToolName,
        description: description(for: openInEditorToolName),
        parameters: ToolRegistry.tool(named: openInEditorToolName)?.parameters ?? []
    )

    private static func description(for tool: String) -> String {
        switch tool {
        case "launch_app":
            return """
            Launch a macOS app and return its pid. Pass app_name (e.g. "Weather", "Safari", \
            "System Settings") or bundle_id; bundle_id wins if both are given. Use the app's \
            English name -- that is what macOS registers even on a Korean system.
            """
        case "list_running_apps":
            return "List the apps currently running, with pid, name and bundle_id. Use this to find a pid before find_ui_element."
        case "get_frontmost_window":
            return """
            Describe the window the user is looking at: owner app, title, and frame. Returns null when             there is none. This is about a *window on screen*, not about files -- it cannot tell you             which directory or project anything is in. For that, use list_files.
            """
        case "find_ui_element":
            return """
            Query an app's Accessibility tree for one element and return its {role, title, frame, enabled}. \
            Needs the app's pid plus role or title_contains. Not finding anything is a success with null \
            data, not an error -- try a different role or title before giving up. Requires Accessibility \
            permission; without it this fails with permission_denied and you should tell the user to grant it.
            """
        case "point_at":
            return """
            Walk the pet to a point on screen and have it point at it. Takes frame \
            {x, y, width, height} in Quartz global screen coordinates (top-left origin, Y down) -- \
            exactly what find_ui_element returns, so pass that through unchanged. This is how you \
            SHOW the user where something is instead of clicking it for them.
            """
        case "click_element":
            return """
            Synthesize a real mouse click at the centre of frame. Requires the user's approval. \
            This does NOT work on macOS system permission or security dialogs -- for those it fails \
            with not_supported_target, and you must fall back to point_at and ask the user to click \
            it themselves.
            """
        case "run_shell":
            return "Run a shell command via /bin/zsh and return stdout, stderr and the exit code. Requires the user's approval."
        case "run_applescript":
            return "Run an AppleScript and return its result as a string. Requires the user's approval. Use this for app automation that has no dedicated tool."
        case openTaskSessionToolName:
            return """
            Move this conversation into a new task session before starting real work. Whenever the \
            user asks for code to be written or changed, call this first and wait for its result; \
            call code_editor on the next turn. `title` is a short label for the sidebar in the user's language \
            (e.g. "hello.ts 주석 추가"); `brief` is one line on what the task is. Everything you say \
            after this lands in the new session, so the casual chat stays readable and the user can \
            stop the coding work without stopping the conversation. Do not call it for questions, \
            explanations, or anything you answer without editing files.
            """
        case codeEditorToolName:
            return """
            Hand a coding task to the workspace editor's own coding agent, which reads and edits the \
            files of the project the user has open and reports back what it changed. Pass `task` as \
            one self-contained instruction in the user's own words -- the editor agent cannot see \
            this conversation, so include everything it needs (which file or feature, what to change, \
            any constraint the user gave). Do NOT pass project_path; the workspace decides that. \
            This is the only way to change files: never use run_shell to edit code. It can take \
            minutes, and the user watches the edit happen in the editor while it runs. Returns the \
            editor agent's summary, or fails with pet_app_disconnected when no workspace is connected \
            -- in which case tell the user to open the workspace app.
            """
        case readFileToolName:
            return """
            Return a file's contents from the project the current workspace has open, read-only. \
            `path` is relative to the project root (or absolute, as long as it's inside the project). \
            Use this to answer questions about code or show the user what a file contains -- it does \
            not open a tab in the editor pane; use open_in_editor for that. Fails with execution_failed \
            if the workspace has no project open, the path doesn't exist, or the file is binary/too large.
            """
        case openInEditorToolName:
            return """
            Open a file as a tab in the client window's editor pane, so the user can see (and, if they \
            choose, edit) it themselves. `path` is relative to the project root. This does not return \
            the file's contents to you -- call read_file first if you need to know what's in it. Use \
            this when the user asks to see or work on a specific file, not as a way to read it yourself.
            """
        default:
            return tool
        }
    }

    private static let systemPrompt = """
    You are the brain of Puck, a desktop pet that carries out the user's requests on their Mac. \
    A 3D pet lives on the screen and physically acts out what you do: it walks to windows, points at \
    things, and reacts to every tool you call. The user sees the pet, not you.

    Rules:
    - Answer in the user's language. Korean input gets Korean answers.
    - Be brief. Say what you did, not how you decided to do it. One or two sentences.
    - Prefer showing over doing: when the user asks where something is, use find_ui_element and then \
      point_at so the pet guides them, rather than clicking it yourself.
    - click_element, run_shell and run_applescript need the user's approval, which costs them an \
      interruption -- reach for them only when no gentler tool does the job.
    - click_element never works on system permission dialogs. When one is involved, point_at it and \
      tell the user to click it themselves.
    - Call tools through the tool interface, one at a time. NEVER write a tool call as text or as \
      a code snippet -- code in your reply is something the user reads, not something that runs. If \
      no tool can do what was asked, say so plainly instead of writing what the call would look like.
    - When the user asks for code to be written or changed, use code_editor if you have it. You \
      never edit files yourself, and the shell is not a substitute for it. If you also have \
      open_task_session, call it first so the editing runs in its own session.
    - If you have read_file, use it (not run_shell/cat) to read or show a file's contents -- it's \
      read-only and costs no approval. Use open_in_editor, if you have it, when the user should see \
      or edit the file themselves instead of just being told what's in it. Neither edits a file; \
      code_editor is the only tool that changes one.
    - When a tool fails with permission_denied, tell the user which permission to grant in System \
      Settings. When it fails with pet_app_disconnected, tell them the pet app isn't running.
    - Never claim you did something a tool did not actually report success for.
    """
}

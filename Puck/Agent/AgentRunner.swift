//
//  AgentRunner.swift
//  Puck
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  The tool-use loop -- plan/04_ai-module.md section 3.2, in Swift.
//
//  byeolki (2026-07-31): "client에 gpt api를 연결해서 이제 펫이 막 화면을
//  컨트롤 하고 날씨 앱 막 켜주고". "날씨 앱 켜줘" reaches here as `run`, the
//  model answers with launch_app, PetToolDispatcher puts that on bridge.sock,
//  pet-app launches it and walks the pet over.
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

final class AgentRunner {
    private let client: GPTClient
    private let dispatcher: PetToolDispatcher
    private let approve: AgentApprovalGate
    private let emit: AgentEventSink

    /// Conversation memory for the session. Per plan/04_ai-module.md 3.4 this
    /// is in-memory only -- persistence is explicitly後순위.
    private var messages: [GPTMessage] = []

    /// A model that keeps calling tools without concluding would otherwise
    /// loop until the API bill says stop. Ten is well past any sequence the
    /// case table describes (the longest is launch → find → point).
    private static let maxTurns = 10

    init(
        client: GPTClient,
        dispatcher: PetToolDispatcher,
        approve: @escaping AgentApprovalGate,
        emit: @escaping AgentEventSink
    ) {
        self.client = client
        self.dispatcher = dispatcher
        self.approve = approve
        self.emit = emit
        messages = [.system(Self.systemPrompt)]
    }

    /// Drops everything but the system prompt -- a new chat session should not
    /// inherit the last one's context.
    func reset() {
        messages = [.system(Self.systemPrompt)]
    }

    func run(command: String) async {
        messages.append(.user(command))
        emit(.agentThinking)

        for _ in 0..<Self.maxTurns {
            let turn: GPTTurn
            do {
                turn = try await client.send(messages: messages, tools: Self.toolSpecs)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                emit(.textChunk(text: reason))
                emit(.agentDone(ok: false, summary: reason))
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
                await perform(call)
            }
        }

        let hitCeiling = "도구를 \(Self.maxTurns)번 넘게 호출해서 중단했어요."
        emit(.textChunk(text: hitCeiling))
        emit(.agentDone(ok: false, summary: hitCeiling))
    }

    private func perform(_ call: GPTToolCall) async {
        let arguments = JSONValue.decodeObject(from: call.argumentsJSON)
        emit(.toolCall(id: call.id, tool: call.name, args: arguments, detail: nil))

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

        let result = await dispatcher.execute(tool: call.name, arguments: arguments)
        report(callId: call.id, ok: result.ok, error: result.error, detail: result.detail, data: result.data)
    }

    /// One place for "tell the model, tell the UI, tell the pet" so a tool
    /// result can never reach one of the three and not the others.
    private func report(callId: String, ok: Bool, error: String?, detail: String?, data: JSONValue?) {
        emit(.toolResult(id: callId, ok: ok, data: data, error: error, detail: detail))
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

    // MARK: - Prompt and tool descriptions

    /// Only pet-app's tools are offered. The three workspace ones are in the
    /// registry but nothing implements them (docs/tools.md marks their
    /// responses TBD), and a tool the model can call but nobody can run is
    /// worse than a missing one.
    private static let toolSpecs: [GPTToolSpec] = ToolRegistry.tools(for: .petApp).map { tool in
        GPTToolSpec(name: tool.name, description: description(for: tool.name), parameters: tool.parameters)
    }

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
            return "Describe the window the user is looking at: owner app, title, and frame. Returns null when there is none."
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
    - When a tool fails with permission_denied, tell the user which permission to grant in System \
      Settings. When it fails with pet_app_disconnected, tell them the pet app isn't running.
    - Never claim you did something a tool did not actually report success for.
    """
}

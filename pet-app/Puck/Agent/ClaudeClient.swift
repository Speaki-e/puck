//
//  ClaudeClient.swift
//  Puck
//
//  F15 (task 3) · owner: 박해영 (Haeyoung Park)
//  A thin Anthropic Messages API client with tool calling -- the second
//  `AgentLLMClient`, sitting next to GPTClient.swift.
//
//  No SDK, same reasoning as GPTClient.swift's header gives: a tool-use loop
//  needs three request fields and reads two response fields, and a
//  dependency for that is a dependency to keep updated. There is also no
//  official Anthropic Swift SDK to reach for.
//
//  The wire format is not Chat Completions with different field names -- four
//  differences that would silently misbehave if copy-pasted from GPTClient:
//
//   1. Auth is `x-api-key` + `anthropic-version`, not `Authorization: Bearer`.
//   2. `system` is a top-level request field, not a `role: "system"` message
//      -- GPTMessage.system is hoisted out of the array during encoding.
//   3. Tool use arrives as content blocks: an assistant reply's `content` is
//      an array mixing text and tool_use blocks. A tool result goes back
//      inside a *user* message as a tool_result block keyed by the
//      original id -- there is no `role: "tool"`.
//   4. `max_tokens` is required (Chat Completions does not require it).
//

import Foundation

final class ClaudeClient: AgentLLMClient {
    /// Read per request, not captured once -- same reasoning as GPTClient:
    /// a key typed into Settings has to take effect without quitting the app.
    private let configuration: () -> AgentConfiguration
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// From `curl/examples.md`'s Required Headers table in the claude-api
    /// skill: `anthropic-version: 2023-06-01` is the one header every request
    /// needs, versioned independently of the model.
    private static let anthropicVersion = "2023-06-01"

    /// The Messages API requires `max_tokens` on every request (Chat
    /// Completions does not). AgentRunner's turns are short tool-call
    /// exchanges, not long-form generation, so a fixed mid-size cap is
    /// simpler than plumbing a per-call value through `AgentLLMClient` for a
    /// need that hasn't come up yet.
    ///
    /// This has to be read together with `thinking` below: `max_tokens` caps
    /// thinking *plus* visible output, so a budget sized only for the answer
    /// gets spent on reasoning and the turn comes back truncated.
    private static let maxTokens = 8192

    init(configuration: @escaping () -> AgentConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        let configuration = configuration()
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else { throw GPTError.notConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": Self.maxTokens,
            // Asked for explicitly rather than left to the model's default.
            // On current Sonnet models an omitted `thinking` means adaptive
            // thinking runs, and its tokens come out of `max_tokens` -- so
            // omitting this silently changes both cost and how much budget is
            // left for the actual answer. It also means thinking blocks come
            // back in `content`, which this client would have to echo into the
            // next assistant turn for a multi-turn tool loop to stay valid.
            // AgentRunner is a short tool-dispatch loop, not a reasoning
            // workload, so turn it off and keep the whole budget for output.
            "thinking": ["type": "disabled"],
            "messages": Self.encodeMessages(messages),
            "tools": tools.map(Self.encode),
        ]
        if let system = Self.system(from: messages) {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTError.malformedResponse("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The body is where Anthropic puts the actual reason (bad key,
            // unknown model, rate limit) -- a bare status code sends whoever
            // is debugging this to the wrong place. Same reasoning as
            // GPTClient.
            throw GPTError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decodeTurn(from: data)
    }

    // MARK: - Wire encoding

    /// `system` is a top-level request field on the Messages API, not a
    /// message with `role: "system"`. Concatenates every `.system` case
    /// found (in order) rather than requiring exactly one, since nothing
    /// upstream guarantees AgentRunner sends only one.
    static func system(from messages: [GPTMessage]) -> String? {
        let systemTexts = messages.compactMap { message -> String? in
            if case .system(let text) = message { return text }
            return nil
        }
        return systemTexts.isEmpty ? nil : systemTexts.joined(separator: "\n\n")
    }

    /// Everything except `.system` cases (hoisted separately into the
    /// top-level `system` field) becomes a `messages` entry.
    ///
    /// Consecutive `.tool` results are merged into ONE user message rather
    /// than one message each. When the model makes parallel tool calls,
    /// `AgentRunner` appends a `.tool` per call, and this API expects every
    /// `tool_result` answering a single assistant turn to come back in the
    /// same user message. Splitting them is accepted (consecutive same-role
    /// messages don't 400) but degrades the model's willingness to fan out
    /// on later turns -- a silent behavioral regression no test would catch.
    static func encodeMessages(_ messages: [GPTMessage]) -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        var pendingToolResults: [[String: Any]] = []

        func flushToolResults() {
            guard !pendingToolResults.isEmpty else { return }
            encoded.append(["role": "user", "content": pendingToolResults])
            pendingToolResults = []
        }

        for message in messages {
            switch message {
            case .system:
                continue
            case .tool(let callId, let content):
                // No `role: "tool"` on this API -- a tool result goes back
                // inside a *user* message as a tool_result block keyed by
                // the tool_use id it answers.
                pendingToolResults.append([
                    "type": "tool_result",
                    "tool_use_id": callId,
                    "content": content,
                ])
            case .user(let text):
                flushToolResults()
                encoded.append(["role": "user", "content": text])
            case .assistant(let text, let toolCalls):
                flushToolResults()
                encoded.append(["role": "assistant", "content": encodeAssistantContent(text: text, toolCalls: toolCalls)])
            }
        }
        flushToolResults()
        return encoded
    }

    /// An assistant turn's `content` is an array mixing a text block (if the
    /// model narrated) with one `tool_use` block per call. At least one
    /// block is required, so a turn with neither becomes an empty string --
    /// matches GPTClient's `content ?? NSNull()` in spirit: present but
    /// empty, not an absent turn.
    private static func encodeAssistantContent(text: String?, toolCalls: [GPTToolCall]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if let text, !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        for call in toolCalls {
            blocks.append([
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                // Anthropic wants the parsed object, not the raw JSON string
                // Chat Completions uses for `arguments` -- decode once here
                // so the wire body carries a real object.
                "input": (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [:],
            ])
        }
        if blocks.isEmpty {
            blocks.append(["type": "text", "text": ""])
        }
        return blocks
    }

    private static func encode(_ tool: GPTToolSpec) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for parameter in tool.parameters {
            properties[parameter.name] = ["type": parameter.type.rawValue]
            if parameter.isRequired { required.append(parameter.name) }
        }
        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required,
            ],
        ]
    }

    // MARK: - Wire decoding

    /// An assistant reply's `content` is an array of blocks -- `text` and
    /// `tool_use` may both appear, same as GPTClient's turn can carry both
    /// narration and calls. Anything else (e.g. `thinking`) is ignored: this
    /// client never asks for it.
    static func decodeTurn(from data: Data) throws -> GPTTurn {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]]
        else {
            throw GPTError.malformedResponse("no content array")
        }

        // Both of these arrive as HTTP 200 with an empty or partial content
        // array, so without this check they decode to a turn with no text and
        // no calls -- which AgentRunner reads as "the model said nothing" and
        // finishes the run ok=true, showing the user nothing at all. Surface
        // them as errors instead so the failure is visible.
        if let stopReason = root["stop_reason"] as? String {
            switch stopReason {
            case "refusal":
                throw GPTError.malformedResponse(Strings.text(.providerRefusedResponse))
            case "max_tokens":
                throw GPTError.malformedResponse(
                    String(format: Strings.text(.providerTruncatedFormat), "\(Self.maxTokens)")
                )
            default:
                break
            }
        }

        var texts: [String] = []
        var calls: [GPTToolCall] = []
        for block in content {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "text":
                if let text = block["text"] as? String { texts.append(text) }
            case "tool_use":
                guard
                    let id = block["id"] as? String,
                    let name = block["name"] as? String
                else { continue }
                // Round-trips the model's parsed `input` back to a JSON
                // string, matching `GPTToolCall.argumentsJSON`'s contract:
                // raw JSON text the caller parses. Absent `input` is a
                // no-parameter tool call -- an empty object, not a failure.
                let input = block["input"] ?? [:]
                let argumentsJSON: String
                if JSONSerialization.isValidJSONObject(input),
                   let encoded = try? JSONSerialization.data(withJSONObject: input) {
                    argumentsJSON = String(data: encoded, encoding: .utf8) ?? "{}"
                } else {
                    argumentsJSON = "{}"
                }
                calls.append(GPTToolCall(id: id, name: name, argumentsJSON: argumentsJSON))
            default:
                continue
            }
        }
        return GPTTurn(text: texts.isEmpty ? nil : texts.joined(separator: "\n"), toolCalls: calls)
    }
}

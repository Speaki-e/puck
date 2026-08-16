//
//  AcpMessages.swift
//  Puck
//
//  The slice of the Agent Client Protocol pet-app actually speaks. The TS side
//  got this from @agentclientprotocol/sdk; there is no Swift SDK, so the six
//  methods AcpAdapter used are hand-rolled here the same way ClaudeClient
//  hand-rolls the Anthropic Messages API.
//
//  Deliberately not a full protocol model: every field the agent sends that we
//  don't name is preserved as JSONValue and passed through, so an agent update
//  we don't understand still reaches the transcript instead of failing to
//  decode. Only the fields that drive behaviour here are typed.
//

import Foundation

enum AcpMethod {
    static let initialize = "initialize"
    static let sessionNew = "session/new"
    static let sessionPrompt = "session/prompt"
    static let sessionCancel = "session/cancel"
    static let sessionUpdate = "session/update"
    static let sessionRequestPermission = "session/request_permission"
}

/// The version claude-agent-acp 0.64.0 and codex-acp 1.2.0 both answer with.
let acpProtocolVersion = 1

// MARK: - Envelope

/// One line of the NDJSON stream. A single frame can be a request, a response,
/// or a notification; which one is decided by which fields are present, so
/// this decodes them all and lets the reader branch.
struct AcpFrame: Decodable {
    let id: JSONValue?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: AcpErrorBody?

    var isResponse: Bool { id != nil && method == nil }
    var isRequest: Bool { id != nil && method != nil }
    var isNotification: Bool { id == nil && method != nil }
}

struct AcpErrorBody: Decodable, Equatable {
    let code: Int
    let message: String
}

// MARK: - Outgoing

enum AcpOutgoing {
    static func request(id: Int, method: String, params: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])
    }

    static func notification(method: String, params: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params,
        ])
    }

    static func response(id: JSONValue, result: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])
    }
}

// MARK: - Session updates

/// A `session/update` notification, kept close to the wire. `raw` is the whole
/// update so callers that want more than the two fields named here (the pet's
/// code_editor path detection, for one) can still reach it.
struct AcpSessionUpdate: Equatable {
    enum Kind: String {
        case agentMessageChunk = "agent_message_chunk"
        case agentThoughtChunk = "agent_thought_chunk"
        case toolCall = "tool_call"
        case toolCallUpdate = "tool_call_update"
        case plan
    }

    let kind: Kind?
    /// Concatenated text for the chunk kinds, empty otherwise.
    let text: String
    let raw: JSONValue

    init(raw: JSONValue) {
        self.raw = raw
        let update = raw.objectValue?["update"] ?? raw
        let kindName = update.objectValue?["sessionUpdate"]?.stringValue
        self.kind = kindName.flatMap(Kind.init(rawValue:))
        if kind == .agentMessageChunk,
           let content = update.objectValue?["content"]?.objectValue,
           content["type"]?.stringValue == "text",
           let text = content["text"]?.stringValue {
            self.text = text
        } else {
            self.text = ""
        }
    }
}

/// Why a prompt turn ended, as `session/prompt` reports it.
struct AcpStopReason: Equatable {
    let rawValue: String

    static let endTurn = AcpStopReason(rawValue: "end_turn")
    static let cancelled = AcpStopReason(rawValue: "cancelled")
}

// MARK: - Permission

/// A `session/request_permission` request from the agent. Options are passed
/// through untouched -- which option means "allow" is the agent's vocabulary,
/// not ours, so the resolver picks by `kind` rather than by a fixed list.
struct AcpPermissionRequest: Equatable {
    struct Option: Equatable {
        let id: String
        let name: String
        /// e.g. "allow_once", "allow_always", "reject_once". Absent on agents
        /// that only send names.
        let kind: String?
    }

    let toolName: String?
    let options: [Option]
    let raw: JSONValue

    init(raw: JSONValue) {
        self.raw = raw
        let params = raw.objectValue
        self.toolName = params?["toolCall"]?.objectValue?["title"]?.stringValue
            ?? params?["toolCall"]?.objectValue?["rawInput"]?.objectValue?["command"]?.stringValue
        self.options = (params?["options"]?.arrayValue ?? []).compactMap { option in
            guard let object = option.objectValue, let id = object["optionId"]?.stringValue else { return nil }
            return Option(
                id: id,
                name: object["name"]?.stringValue ?? id,
                kind: object["kind"]?.stringValue
            )
        }
    }

    /// The option to send back for an approval, or nil when the agent offered
    /// none that allow -- in which case cancelling is the only honest answer.
    /// Never falls back to "whatever came first": an agent that omits `kind`
    /// and happens to list its rejection first would turn the user's approval
    /// into a refusal, which is the one direction this must not get wrong.
    func allowOption() -> Option? {
        options.first { $0.kind == "allow_once" }
            ?? options.first { $0.kind?.hasPrefix("allow") == true }
    }

    func rejectOption() -> Option? {
        options.first { $0.kind == "reject_once" }
            ?? options.first { $0.kind?.hasPrefix("reject") == true }
    }

    static func outcome(selecting optionId: String) -> JSONValue {
        .object(["outcome": .object([
            "outcome": .string("selected"),
            "optionId": .string(optionId),
        ])])
    }

    static func cancelledOutcome() -> JSONValue {
        .object(["outcome": .object(["outcome": .string("cancelled")])])
    }
}

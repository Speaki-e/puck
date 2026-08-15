//
//  BridgeMessages.swift
//  Puck
//
//  F11/socket · owner: 박해영 (Haeyoung Park)
//  Mirrors protocol repo's /swift/BridgeMessages.swift (Codable message types).
//  Schema source: plan/01_protocol.md section 3. Always update this file together
//  with the protocol repo's schema.
//

/// Standard tool_result error codes that cross the socket (protocol 3.1).
/// `denied_by_user` is deliberately excluded -- approval happens inside the
/// agent before dispatch, so it never reaches pet-app/workspace on the wire.
enum ToolErrorCode: String, Codable, Equatable {
    case timeout = "timeout"
    case petAppDisconnected = "pet_app_disconnected"
    case permissionDenied = "permission_denied"
    case notSupportedTarget = "not_supported_target"
    case executionFailed = "execution_failed"
    case unknownTool = "unknown_tool"
    case cancelled = "cancelled"
}

/// workspace -> pet-app: tool execution request (protocol 3.1)
struct ToolDispatch: Equatable {
    let id: String
    let tool: String
    let args: JSONValue
}

/// pet-app -> workspace: tool execution result (protocol 3.1)
struct ToolResult: Equatable {
    let id: String
    let ok: Bool
    let data: JSONValue?
    /// Standard error code (timeout, unknown_tool, execution_failed, ...).
    let error: ToolErrorCode?
    /// Human-readable failure specifics (optional) -- the code alone says
    /// *what kind* of failure; this says *what actually happened*, so the
    /// real reason reaches the wire and the logs (protocol 3.1).
    let detail: String?

    init(id: String, ok: Bool, data: JSONValue?, error: ToolErrorCode?, detail: String? = nil) {
        self.id = id
        self.ok = ok
        self.data = data
        self.error = error
        self.detail = detail
    }
}

/// workspace -> pet-app: state events driving the pet's reactions (protocol 3.2).
///
/// awaitApproval's approvalId (2026-07-29) exists because the approval UI itself now
/// lives in pet-app's F13 client window rather than workspace's own renderer --
/// resolving it has to round-trip the socket via ApprovalResponse (protocol 3.6), so
/// the event needs enough to route that response to the right pending resolve.
/// workspaceId/sessionId live on BridgeMessage.event's wrapper, not here -- every
/// event kind needs them once more than one session can be open, not just this one.
///
/// textChunk, and toolCall/toolResult's id/args/data/error/detail (2026-07-29) exist
/// because this stream now feeds two audiences, not just the pet's reactions: pet-app's
/// F13 chat view needs a real timeline (streaming assistant text, which tool ran with
/// what args, what it actually returned) -- effectively AgentCallbacks proxied over the
/// socket. toolCall.detail is unchanged from its original purpose (a curated summary,
/// e.g. code_editor's path) and is distinct from args (the tool's raw call arguments).
enum BridgeEvent: Equatable {
    case agentThinking
    case textChunk(text: String)
    case toolCall(id: String, tool: String, args: JSONValue?, detail: JSONValue?)
    case toolResult(id: String, ok: Bool, data: JSONValue?, error: ToolErrorCode?, detail: String?)
    case awaitApproval(summary: String, approvalId: String)
    case agentDone(ok: Bool, summary: String)
}

/// An image attached to a user_input (e.g. pet-app's F14 drag capture).
struct Attachment: Equatable {
    /// Local temp file path on the same machine -- not base64, to keep the socket message small.
    let path: String
}

extension Attachment: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "image" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown attachment type \(type)")
        }
        self.path = try container.decode(String.self, forKey: .path)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("image", forKey: .type)
        try container.encode(path, forKey: .path)
    }
}

/// pet-app -> workspace: voice/text command input (protocol 3.3).
///
/// workspaceId/sessionId (2026-07-29, protocol 3.4) default to "default" when absent --
/// existing single-workspace/single-session consumers are unaffected.
struct UserInput: Equatable {
    enum Source: String, Codable {
        case voice
        case text
    }

    let text: String
    let source: Source
    let workspaceId: String?
    let sessionId: String?
    let attachments: [Attachment]?

    init(text: String, source: Source, workspaceId: String? = nil, sessionId: String? = nil, attachments: [Attachment]? = nil) {
        self.text = text
        self.source = source
        self.workspaceId = workspaceId
        self.sessionId = sessionId
        self.attachments = attachments
    }
}

/// Who created a session: user via the sidebar's "new chat", or agent when it branched
/// a casual conversation into a task session on its own judgement (protocol 4,
/// plan/04_ai-module.md 3.7).
enum SessionOrigin: String, Codable {
    case user
    case agent
}


/// Who is on the other end of a bridge.sock connection. Only `gui` remains:
/// the `workspace` role named the Electron backend, which was deleted on
/// 2026-08-15 once pet-app took over the registries and code_editor. The enum
/// stays rather than collapsing to nothing because client_hello still carries
/// a role on the wire, and an unknown value has to be rejected rather than
/// assumed. Sent once, right after connecting.
///
/// Relay targets now: user_input/event/workspace_create/session_create reach
/// gui connections; everything else is handled where it lands (ClientRelay).
enum ClientRole: String, Codable {
    case gui
}

/// Top-level type for every JSON Lines message on the socket, discriminated by "type".
enum BridgeMessage: Equatable {
    /// Either side -> pet-app: identifies which role this connection plays (protocol 3.7).
    case clientHello(role: ClientRole)
    case toolDispatch(ToolDispatch)
    /// workspace -> pet-app: abandon an in-flight dispatch (protocol 3.1) --
    /// the handler is cancelled and the original id replies error="cancelled".
    /// Unknown/already-completed ids are ignored (idempotent).
    case toolCancel(id: String)
    case toolResult(ToolResult)
    /// workspaceId/sessionId (2026-07-29) route the event to the right chat
    /// session in pet-app's F13 client window -- without them, once more than
    /// one session is open, pet-app has no way to tell which session's
    /// timeline an incoming event belongs to.
    case event(BridgeEvent, workspaceId: String, sessionId: String)
    case userInput(UserInput)

    // --- sessions/workspaces (2026-07-29, protocol 3.4) ---

    /// pet-app -> workspace: request a new workspace (project folder or pure-chat).
    /// Confirmed by workspaceCreate, which assigns workspaceId.
    case workspaceCreateRequest(name: String, projectPath: String?)
    /// workspace -> pet-app: confirms a workspace now exists.
    case workspaceCreate(workspaceId: String, name: String, projectPath: String?)
    /// pet-app -> workspace: request a new chat session under a workspace.
    /// Confirmed by sessionCreate, which assigns sessionId.
    case sessionCreateRequest(workspaceId: String, title: String)
    /// workspace -> pet-app: confirms a session now exists.
    case sessionCreate(workspaceId: String, sessionId: String, title: String, origin: SessionOrigin)


    // --- approval response / run cancel (2026-07-29, protocol 3.6) ---

    /// pet-app -> workspace: resolve a pending awaitApproval by id. Unknown/already-resolved
    /// ids are ignored (idempotent).
    case approvalResponse(approvalId: String, approved: Bool)
    /// pet-app -> workspace: abort the in-flight run() for a session -- the whole
    /// conversation turn, a different level from toolCancel (which abandons one tool dispatch).
    case runCancel(sessionId: String)
}

extension BridgeMessage: Codable {
    private enum TypeKey: String, Codable {
        case clientHello = "client_hello"
        case toolDispatch = "tool_dispatch"
        case toolCancel = "tool_cancel"
        case toolResult = "tool_result"
        case event = "event"
        case userInput = "user_input"
        case workspaceCreateRequest = "workspace_create_request"
        case workspaceCreate = "workspace_create"
        case sessionCreateRequest = "session_create_request"
        case sessionCreate = "session_create"
        case approvalResponse = "approval_response"
        case runCancel = "run_cancel"
    }

    private enum EventKey: String, Codable {
        case agentThinking = "agent_thinking"
        case textChunk = "text_chunk"
        case toolCall = "tool_call"
        case toolResult = "tool_result"
        case awaitApproval = "await_approval"
        case agentDone = "agent_done"
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, tool, args, ok, data, error, event, detail, summary, text, source
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
        case attachments
        case name
        case projectPath = "project_path"
        case title
        case origin
        case url
        case reason
        case approvalId = "approval_id"
        case approved
        case role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(TypeKey.self, forKey: .type) {
        case .clientHello:
            self = .clientHello(role: try container.decode(ClientRole.self, forKey: .role))

        case .toolDispatch:
            self = .toolDispatch(
                ToolDispatch(
                    id: try container.decode(String.self, forKey: .id),
                    tool: try container.decode(String.self, forKey: .tool),
                    args: try container.decodeIfPresent(JSONValue.self, forKey: .args) ?? .object([:])
                )
            )

        case .toolCancel:
            self = .toolCancel(id: try container.decode(String.self, forKey: .id))

        case .toolResult:
            self = .toolResult(
                ToolResult(
                    id: try container.decode(String.self, forKey: .id),
                    ok: try container.decode(Bool.self, forKey: .ok),
                    data: try container.decodeIfPresent(JSONValue.self, forKey: .data),
                    error: try container.decodeIfPresent(ToolErrorCode.self, forKey: .error),
                    detail: try container.decodeIfPresent(String.self, forKey: .detail)
                )
            )

        case .event:
            let workspaceId = try container.decode(String.self, forKey: .workspaceId)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let event: BridgeEvent
            switch try container.decode(EventKey.self, forKey: .event) {
            case .agentThinking:
                event = .agentThinking
            case .textChunk:
                event = .textChunk(text: try container.decode(String.self, forKey: .text))
            case .toolCall:
                event = .toolCall(
                    id: try container.decode(String.self, forKey: .id),
                    tool: try container.decode(String.self, forKey: .tool),
                    args: try container.decodeIfPresent(JSONValue.self, forKey: .args),
                    detail: try container.decodeIfPresent(JSONValue.self, forKey: .detail)
                )
            case .toolResult:
                event = .toolResult(
                    id: try container.decode(String.self, forKey: .id),
                    ok: try container.decode(Bool.self, forKey: .ok),
                    data: try container.decodeIfPresent(JSONValue.self, forKey: .data),
                    error: try container.decodeIfPresent(ToolErrorCode.self, forKey: .error),
                    detail: try container.decodeIfPresent(String.self, forKey: .detail)
                )
            case .awaitApproval:
                event = .awaitApproval(
                    summary: try container.decode(String.self, forKey: .summary),
                    approvalId: try container.decode(String.self, forKey: .approvalId)
                )
            case .agentDone:
                event = .agentDone(
                    ok: try container.decode(Bool.self, forKey: .ok),
                    summary: try container.decode(String.self, forKey: .summary)
                )
            }
            self = .event(event, workspaceId: workspaceId, sessionId: sessionId)

        case .userInput:
            self = .userInput(
                UserInput(
                    text: try container.decode(String.self, forKey: .text),
                    source: try container.decode(UserInput.Source.self, forKey: .source),
                    workspaceId: try container.decodeIfPresent(String.self, forKey: .workspaceId),
                    sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId),
                    attachments: try container.decodeIfPresent([Attachment].self, forKey: .attachments)
                )
            )

        case .workspaceCreateRequest:
            self = .workspaceCreateRequest(
                name: try container.decode(String.self, forKey: .name),
                projectPath: try container.decodeIfPresent(String.self, forKey: .projectPath)
            )

        case .workspaceCreate:
            self = .workspaceCreate(
                workspaceId: try container.decode(String.self, forKey: .workspaceId),
                name: try container.decode(String.self, forKey: .name),
                projectPath: try container.decodeIfPresent(String.self, forKey: .projectPath)
            )

        case .sessionCreateRequest:
            self = .sessionCreateRequest(
                workspaceId: try container.decode(String.self, forKey: .workspaceId),
                title: try container.decode(String.self, forKey: .title)
            )

        case .sessionCreate:
            self = .sessionCreate(
                workspaceId: try container.decode(String.self, forKey: .workspaceId),
                sessionId: try container.decode(String.self, forKey: .sessionId),
                title: try container.decode(String.self, forKey: .title),
                origin: try container.decode(SessionOrigin.self, forKey: .origin)
            )


        case .approvalResponse:
            self = .approvalResponse(
                approvalId: try container.decode(String.self, forKey: .approvalId),
                approved: try container.decode(Bool.self, forKey: .approved)
            )

        case .runCancel:
            self = .runCancel(sessionId: try container.decode(String.self, forKey: .sessionId))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .clientHello(let role):
            try container.encode(TypeKey.clientHello, forKey: .type)
            try container.encode(role, forKey: .role)

        case .toolDispatch(let dispatch):
            try container.encode(TypeKey.toolDispatch, forKey: .type)
            try container.encode(dispatch.id, forKey: .id)
            try container.encode(dispatch.tool, forKey: .tool)
            try container.encode(dispatch.args, forKey: .args)

        case .toolCancel(let id):
            try container.encode(TypeKey.toolCancel, forKey: .type)
            try container.encode(id, forKey: .id)

        case .toolResult(let result):
            try container.encode(TypeKey.toolResult, forKey: .type)
            try container.encode(result.id, forKey: .id)
            try container.encode(result.ok, forKey: .ok)
            try container.encodeIfPresent(result.data, forKey: .data)
            try container.encodeIfPresent(result.error, forKey: .error)
            try container.encodeIfPresent(result.detail, forKey: .detail)

        case .event(let event, let workspaceId, let sessionId):
            try container.encode(TypeKey.event, forKey: .type)
            try container.encode(workspaceId, forKey: .workspaceId)
            try container.encode(sessionId, forKey: .sessionId)
            switch event {
            case .agentThinking:
                try container.encode(EventKey.agentThinking, forKey: .event)
            case .textChunk(let text):
                try container.encode(EventKey.textChunk, forKey: .event)
                try container.encode(text, forKey: .text)
            case .toolCall(let id, let tool, let args, let detail):
                try container.encode(EventKey.toolCall, forKey: .event)
                try container.encode(id, forKey: .id)
                try container.encode(tool, forKey: .tool)
                try container.encodeIfPresent(args, forKey: .args)
                try container.encodeIfPresent(detail, forKey: .detail)
            case .toolResult(let id, let ok, let data, let error, let detail):
                try container.encode(EventKey.toolResult, forKey: .event)
                try container.encode(id, forKey: .id)
                try container.encode(ok, forKey: .ok)
                try container.encodeIfPresent(data, forKey: .data)
                try container.encodeIfPresent(error, forKey: .error)
                try container.encodeIfPresent(detail, forKey: .detail)
            case .awaitApproval(let summary, let approvalId):
                try container.encode(EventKey.awaitApproval, forKey: .event)
                try container.encode(summary, forKey: .summary)
                try container.encode(approvalId, forKey: .approvalId)
            case .agentDone(let ok, let summary):
                try container.encode(EventKey.agentDone, forKey: .event)
                try container.encode(ok, forKey: .ok)
                try container.encode(summary, forKey: .summary)
            }

        case .userInput(let input):
            try container.encode(TypeKey.userInput, forKey: .type)
            try container.encode(input.text, forKey: .text)
            try container.encode(input.source, forKey: .source)
            try container.encodeIfPresent(input.workspaceId, forKey: .workspaceId)
            try container.encodeIfPresent(input.sessionId, forKey: .sessionId)
            try container.encodeIfPresent(input.attachments, forKey: .attachments)

        case .workspaceCreateRequest(let name, let projectPath):
            try container.encode(TypeKey.workspaceCreateRequest, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(projectPath, forKey: .projectPath)

        case .workspaceCreate(let workspaceId, let name, let projectPath):
            try container.encode(TypeKey.workspaceCreate, forKey: .type)
            try container.encode(workspaceId, forKey: .workspaceId)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(projectPath, forKey: .projectPath)

        case .sessionCreateRequest(let workspaceId, let title):
            try container.encode(TypeKey.sessionCreateRequest, forKey: .type)
            try container.encode(workspaceId, forKey: .workspaceId)
            try container.encode(title, forKey: .title)

        case .sessionCreate(let workspaceId, let sessionId, let title, let origin):
            try container.encode(TypeKey.sessionCreate, forKey: .type)
            try container.encode(workspaceId, forKey: .workspaceId)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(title, forKey: .title)
            try container.encode(origin, forKey: .origin)


        case .approvalResponse(let approvalId, let approved):
            try container.encode(TypeKey.approvalResponse, forKey: .type)
            try container.encode(approvalId, forKey: .approvalId)
            try container.encode(approved, forKey: .approved)

        case .runCancel(let sessionId):
            try container.encode(TypeKey.runCancel, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        }
    }
}

//
//  BridgeMessages.swift
//  PetAgent
//
//  F11/소켓 · 담당: 박해영
//  protocol 저장소 /swift/BridgeMessages.swift 동기화 사본 (Codable 메시지 타입)
//  스키마 근거: plan/01_protocol.md 3절. 이 파일과 protocol 저장소 스키마는 항상 같이 수정한다.
//

/// workspace -> pet-app: 도구 실행 요청 (protocol 3.1)
struct ToolDispatch: Equatable {
    let id: String
    let tool: String
    let args: JSONValue
}

/// pet-app -> workspace: 도구 실행 결과 (protocol 3.1)
struct ToolResult: Equatable {
    let id: String
    let ok: Bool
    let data: JSONValue?
    let error: String?
}

/// workspace -> pet-app: 펫 반응용 상태 이벤트 (protocol 3.2)
enum BridgeEvent: Equatable {
    case agentThinking
    case toolCall(tool: String, detail: JSONValue?)
    case toolResult(ok: Bool)
    case awaitApproval(summary: String)
    case agentDone(ok: Bool, summary: String)
}

/// pet-app -> workspace: 음성/텍스트 명령 입력 (protocol 3.3)
struct UserInput: Equatable {
    enum Source: String, Codable {
        case voice
        case text
    }

    let text: String
    let source: Source
}

/// 소켓으로 오가는 모든 JSON Lines 메시지의 최상위 타입. "type" 필드로 구분한다.
enum BridgeMessage: Equatable {
    case toolDispatch(ToolDispatch)
    case toolResult(ToolResult)
    case event(BridgeEvent)
    case userInput(UserInput)
}

extension BridgeMessage: Codable {
    private enum TypeKey: String, Codable {
        case toolDispatch = "tool_dispatch"
        case toolResult = "tool_result"
        case event = "event"
        case userInput = "user_input"
    }

    private enum EventKey: String, Codable {
        case agentThinking = "agent_thinking"
        case toolCall = "tool_call"
        case toolResult = "tool_result"
        case awaitApproval = "await_approval"
        case agentDone = "agent_done"
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, tool, args, ok, data, error, event, detail, summary, text, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(TypeKey.self, forKey: .type) {
        case .toolDispatch:
            self = .toolDispatch(
                ToolDispatch(
                    id: try container.decode(String.self, forKey: .id),
                    tool: try container.decode(String.self, forKey: .tool),
                    args: try container.decodeIfPresent(JSONValue.self, forKey: .args) ?? .object([:])
                )
            )

        case .toolResult:
            self = .toolResult(
                ToolResult(
                    id: try container.decode(String.self, forKey: .id),
                    ok: try container.decode(Bool.self, forKey: .ok),
                    data: try container.decodeIfPresent(JSONValue.self, forKey: .data),
                    error: try container.decodeIfPresent(String.self, forKey: .error)
                )
            )

        case .event:
            switch try container.decode(EventKey.self, forKey: .event) {
            case .agentThinking:
                self = .event(.agentThinking)
            case .toolCall:
                self = .event(
                    .toolCall(
                        tool: try container.decode(String.self, forKey: .tool),
                        detail: try container.decodeIfPresent(JSONValue.self, forKey: .detail)
                    )
                )
            case .toolResult:
                self = .event(.toolResult(ok: try container.decode(Bool.self, forKey: .ok)))
            case .awaitApproval:
                self = .event(.awaitApproval(summary: try container.decode(String.self, forKey: .summary)))
            case .agentDone:
                self = .event(
                    .agentDone(
                        ok: try container.decode(Bool.self, forKey: .ok),
                        summary: try container.decode(String.self, forKey: .summary)
                    )
                )
            }

        case .userInput:
            self = .userInput(
                UserInput(
                    text: try container.decode(String.self, forKey: .text),
                    source: try container.decode(UserInput.Source.self, forKey: .source)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .toolDispatch(let dispatch):
            try container.encode(TypeKey.toolDispatch, forKey: .type)
            try container.encode(dispatch.id, forKey: .id)
            try container.encode(dispatch.tool, forKey: .tool)
            try container.encode(dispatch.args, forKey: .args)

        case .toolResult(let result):
            try container.encode(TypeKey.toolResult, forKey: .type)
            try container.encode(result.id, forKey: .id)
            try container.encode(result.ok, forKey: .ok)
            try container.encodeIfPresent(result.data, forKey: .data)
            try container.encodeIfPresent(result.error, forKey: .error)

        case .event(let event):
            try container.encode(TypeKey.event, forKey: .type)
            switch event {
            case .agentThinking:
                try container.encode(EventKey.agentThinking, forKey: .event)
            case .toolCall(let tool, let detail):
                try container.encode(EventKey.toolCall, forKey: .event)
                try container.encode(tool, forKey: .tool)
                try container.encodeIfPresent(detail, forKey: .detail)
            case .toolResult(let ok):
                try container.encode(EventKey.toolResult, forKey: .event)
                try container.encode(ok, forKey: .ok)
            case .awaitApproval(let summary):
                try container.encode(EventKey.awaitApproval, forKey: .event)
                try container.encode(summary, forKey: .summary)
            case .agentDone(let ok, let summary):
                try container.encode(EventKey.agentDone, forKey: .event)
                try container.encode(ok, forKey: .ok)
                try container.encode(summary, forKey: .summary)
            }

        case .userInput(let input):
            try container.encode(TypeKey.userInput, forKey: .type)
            try container.encode(input.text, forKey: .text)
            try container.encode(input.source, forKey: .source)
        }
    }
}

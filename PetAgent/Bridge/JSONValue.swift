//
//  JSONValue.swift
//  PetAgent
//
//  F11/소켓 · 담당: 박해영
//  BridgeMessages의 자유 형식 필드(args/data/detail)를 표현하는 최소 JSON 트리
//

/// tool_dispatch.args, tool_result.data, event(tool_call).detail처럼 도구별로 모양이 달라지는
/// 필드를 표현한다. protocol 저장소 스키마가 이 필드들의 내부 구조를 규정하지 않으므로,
/// pet-app 쪽은 구조를 강제하지 않고 그대로 보존/전달한다.
enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "지원하지 않는 JSON 값"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

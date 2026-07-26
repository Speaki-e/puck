//
//  BridgeMessageCodableTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  Verifies BridgeMessages Codable encoding/decoding against the example JSON
//  in plan/01_protocol.md section 3.
//

import XCTest
@testable import PetAgent

final class BridgeMessageCodableTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - tool_dispatch (workspace -> pet-app)

    func test_decodesToolDispatch() throws {
        let json = #"{"type":"tool_dispatch","id":"t1","tool":"launch_app","args":{"app_name":"Safari"}}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        guard case .toolDispatch(let dispatch) = message else {
            return XCTFail("expected .toolDispatch, got \(message)")
        }
        XCTAssertEqual(dispatch.id, "t1")
        XCTAssertEqual(dispatch.tool, "launch_app")
        XCTAssertEqual(dispatch.args, .object(["app_name": .string("Safari")]))
    }

    func test_encodesToolDispatch_roundTrips() throws {
        let original = BridgeMessage.toolDispatch(
            ToolDispatch(id: "t1", tool: "launch_app", args: .object(["app_name": .string("Safari")]))
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - tool_result (pet-app -> workspace)

    func test_decodesToolResult_success() throws {
        let json = #"{"type":"tool_result","id":"t1","ok":true,"data":{"pid":501}}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        guard case .toolResult(let result) = message else {
            return XCTFail("expected .toolResult, got \(message)")
        }
        XCTAssertEqual(result.id, "t1")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.data, .object(["pid": .number(501)]))
        XCTAssertNil(result.error)
    }

    func test_decodesToolResult_failure() throws {
        let json = #"{"type":"tool_result","id":"t1","ok":false,"error":"timeout"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        guard case .toolResult(let result) = message else {
            return XCTFail("expected .toolResult, got \(message)")
        }
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "timeout")
        XCTAssertNil(result.data)
    }

    // MARK: - event (workspace -> pet-app, drives the pet's reactions)

    func test_decodesEvent_agentThinking() throws {
        let json = #"{"type":"event","event":"agent_thinking"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.agentThinking))
    }

    func test_decodesEvent_toolCall_withDetail() throws {
        let json = #"{"type":"event","event":"tool_call","tool":"code_editor","detail":{"path":"src/main.ts"}}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        guard case .event(.toolCall(let tool, let detail)) = message else {
            return XCTFail("expected .event(.toolCall), got \(message)")
        }
        XCTAssertEqual(tool, "code_editor")
        XCTAssertEqual(detail, .object(["path": .string("src/main.ts")]))
    }

    func test_decodesEvent_toolResult() throws {
        let json = #"{"type":"event","event":"tool_result","ok":true}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.toolResult(ok: true)))
    }

    func test_decodesEvent_awaitApproval() throws {
        let json = #"{"type":"event","event":"await_approval","summary":"rm -rf ./dist 실행 요청"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.awaitApproval(summary: "rm -rf ./dist 실행 요청")))
    }

    func test_decodesEvent_agentDone() throws {
        let json = #"{"type":"event","event":"agent_done","ok":true,"summary":"테스트 3건 통과"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.agentDone(ok: true, summary: "테스트 3건 통과")))
    }

    // MARK: - user_input (pet-app -> workspace)

    func test_decodesUserInput_voice() throws {
        let json = #"{"type":"user_input","text":"이 프로젝트 테스트 돌려줘","source":"voice"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .userInput(UserInput(text: "이 프로젝트 테스트 돌려줘", source: .voice)))
    }

    func test_encodesUserInput_text_roundTrips() throws {
        let original = BridgeMessage.userInput(UserInput(text: "README 열어줘", source: .text))

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Error handling

    func test_decodingUnknownType_throws() {
        let json = #"{"type":"something_else"}"#

        XCTAssertThrowsError(try decoder.decode(BridgeMessage.self, from: Data(json.utf8)))
    }
}

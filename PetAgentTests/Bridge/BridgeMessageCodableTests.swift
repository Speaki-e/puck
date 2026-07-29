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
        XCTAssertNil(result.detail)
    }

    /// protocol 3.1: workspace can abandon an in-flight dispatch (user pressed
    /// stop, or the 600s code_editor budget was pulled) -- pet-app cancels the
    /// handler and replies error="cancelled".
    func test_decodesToolCancel() throws {
        let json = #"{"type":"tool_cancel","id":"t1"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .toolCancel(id: "t1"))
    }

    func test_toolCancel_roundTrips() throws {
        let original = BridgeMessage.toolCancel(id: "t42")

        let encoded = try JSONEncoder().encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    /// protocol 3.1: `error` is the standard code, `detail` (optional) carries
    /// the human-readable specifics for logs/debugging.
    func test_toolResultDetail_roundTrips() throws {
        let original = BridgeMessage.toolResult(
            ToolResult(id: "t1", ok: false, data: nil, error: "execution_failed", detail: "zsh exited 127")
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: encoded)

        XCTAssertEqual(decoded, original)
        guard case .toolResult(let result) = decoded else {
            return XCTFail("expected .toolResult, got \(decoded)")
        }
        XCTAssertEqual(result.detail, "zsh exited 127")
    }

    // MARK: - event (workspace -> pet-app, drives the pet's reactions)

    func test_decodesEvent_agentThinking() throws {
        let json = #"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.agentThinking, workspaceId: "default", sessionId: "default"))
    }

    func test_decodesEvent_toolCall_withDetail() throws {
        let json = #"{"type":"event","event":"tool_call","tool":"code_editor","detail":{"path":"src/main.ts"},"workspace_id":"w1","session_id":"s2"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        guard case .event(.toolCall(let tool, let detail), let workspaceId, let sessionId) = message else {
            return XCTFail("expected .event(.toolCall), got \(message)")
        }
        XCTAssertEqual(tool, "code_editor")
        XCTAssertEqual(detail, .object(["path": .string("src/main.ts")]))
        XCTAssertEqual(workspaceId, "w1")
        XCTAssertEqual(sessionId, "s2")
    }

    func test_decodesEvent_toolResult() throws {
        let json = #"{"type":"event","event":"tool_result","ok":true,"workspace_id":"default","session_id":"default"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.toolResult(ok: true), workspaceId: "default", sessionId: "default"))
    }

    func test_decodesEvent_awaitApproval() throws {
        let json = #"{"type":"event","event":"await_approval","summary":"rm -rf ./dist 실행 요청","approval_id":"a1","workspace_id":"w1","session_id":"s2"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(
            message,
            .event(.awaitApproval(summary: "rm -rf ./dist 실행 요청", approvalId: "a1"), workspaceId: "w1", sessionId: "s2")
        )
    }

    func test_decodesEvent_agentDone() throws {
        let json = #"{"type":"event","event":"agent_done","ok":true,"summary":"테스트 3건 통과","workspace_id":"default","session_id":"default"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .event(.agentDone(ok: true, summary: "테스트 3건 통과"), workspaceId: "default", sessionId: "default"))
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

    /// 2026-07-29 (plan/01_protocol.md 3.4): workspace_id/session_id default to
    /// "default" when a single-workspace/single-session caller omits them.
    func test_decodesUserInput_withWorkspaceSessionAndAttachments() throws {
        let json = #"""
        {"type":"user_input","text":"look at this","source":"text","workspace_id":"w1","session_id":"s2","attachments":[{"type":"image","path":"/tmp/capture.png"}]}
        """#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(
            message,
            .userInput(UserInput(text: "look at this", source: .text, workspaceId: "w1", sessionId: "s2", attachments: [Attachment(path: "/tmp/capture.png")]))
        )
    }

    // MARK: - sessions/workspaces (pet-app <-> workspace, 2026-07-29)

    func test_encodesWorkspaceCreateRequest_roundTrips() throws {
        let original = BridgeMessage.workspaceCreateRequest(name: "cat house", projectPath: "/tmp/cat-house")

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_decodesWorkspaceCreate_withNoProjectPath() throws {
        let json = #"{"type":"workspace_create","workspace_id":"w1","name":"chat only"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .workspaceCreate(workspaceId: "w1", name: "chat only", projectPath: nil))
    }

    func test_encodesSessionCreateRequest_roundTrips() throws {
        let original = BridgeMessage.sessionCreateRequest(workspaceId: "w1", title: "new chat")

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_decodesSessionCreate_agentOrigin() throws {
        let json = #"{"type":"session_create","workspace_id":"w1","session_id":"s2","title":"fix the bug","origin":"agent"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .sessionCreate(workspaceId: "w1", sessionId: "s2", title: "fix the bug", origin: .agent))
    }

    // MARK: - editor view (workspace -> pet-app, 2026-07-29)

    func test_decodesEditorViewReady() throws {
        let json = #"{"type":"editor_view_ready","workspace_id":"w1","url":"http://127.0.0.1:53912/editor"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .editorViewReady(workspaceId: "w1", url: "http://127.0.0.1:53912/editor"))
    }

    func test_decodesEditorViewUnavailable() throws {
        let json = #"{"type":"editor_view_unavailable","workspace_id":"w1","reason":"no_project_path"}"#
        let message = try decoder.decode(BridgeMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message, .editorViewUnavailable(workspaceId: "w1", reason: .noProjectPath))
    }

    // MARK: - approval response / run cancel (pet-app -> workspace, 2026-07-29)

    func test_encodesApprovalResponse_roundTrips() throws {
        let original = BridgeMessage.approvalResponse(approvalId: "a1", approved: true)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BridgeMessage.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_encodesRunCancel_roundTrips() throws {
        let original = BridgeMessage.runCancel(sessionId: "s2")

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

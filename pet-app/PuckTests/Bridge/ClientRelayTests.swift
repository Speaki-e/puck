//
//  ClientRelayTests.swift
//  Puck
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Puck

final class ClientRelayTests: XCTestCase {
    func test_guiOriginatedMessages_targetWorkspace() {
        XCTAssertEqual(ClientRelay.targetRole(for: .userInput(UserInput(text: "hi", source: .text))), .workspace)
        XCTAssertEqual(ClientRelay.targetRole(for: .approvalResponse(approvalId: "a1", approved: true)), .workspace)
        XCTAssertEqual(ClientRelay.targetRole(for: .runCancel(sessionId: "s1")), .workspace)
    }

    func test_workspaceOriginatedMessages_targetGUI() {
        XCTAssertEqual(ClientRelay.targetRole(for: .event(.agentThinking, workspaceId: "w1", sessionId: "s1")), .gui)
        XCTAssertEqual(ClientRelay.targetRole(for: .workspaceCreate(workspaceId: "w1", name: "cat house", projectPath: nil)), .gui)
        XCTAssertEqual(ClientRelay.targetRole(for: .sessionCreate(workspaceId: "w1", sessionId: "s1", title: "new chat", origin: .user)), .gui)
        XCTAssertEqual(ClientRelay.targetRole(for: .editorViewReady(workspaceId: "w1", url: "http://127.0.0.1:1/e")), .gui)
        XCTAssertEqual(ClientRelay.targetRole(for: .editorViewUnavailable(workspaceId: "w1", reason: .noProjectPath)), .gui)
    }

    func test_locallyHandledMessages_haveNoTargetRole() {
        // The two create requests joined this list on 2026-08-15: pet-app owns
        // WorkspaceRegistry now, so BridgeMessageRouter answers them in-process
        // instead of relaying them to workspace. See WorkspaceCoordinatorTests.
        XCTAssertNil(ClientRelay.targetRole(for: .workspaceCreateRequest(name: "cat house", projectPath: nil)))
        XCTAssertNil(ClientRelay.targetRole(for: .sessionCreateRequest(workspaceId: "w1", title: "new chat")))
        XCTAssertNil(ClientRelay.targetRole(for: .clientHello(role: .gui)))
        XCTAssertNil(ClientRelay.targetRole(for: .toolDispatch(ToolDispatch(id: "t1", tool: "launch_app", args: .object([:])))))
        XCTAssertNil(ClientRelay.targetRole(for: .toolCancel(id: "t1")))
        XCTAssertNil(ClientRelay.targetRole(for: .toolResult(ToolResult(id: "t1", ok: true, data: nil, error: nil))))
    }
}

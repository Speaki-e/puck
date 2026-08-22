//
//  AgentPermissionModeTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class AgentPermissionModeTests: XCTestCase {
    private func request(kind: String?, tool: String = "Write") -> AcpPermissionRequest {
        var call: [String: JSONValue] = ["title": .string(tool)]
        if let kind { call["kind"] = .string(kind) }
        return AcpPermissionRequest(raw: .object([
            "toolCall": .object(call),
            "options": .array([
                .object(["optionId": .string("a"), "kind": .string("allow_once")]),
                .object(["optionId": .string("r"), "kind": .string("reject_once")]),
            ]),
        ]))
    }

    private let server = "puck"

    /// Turning a CLI loose on a filesystem has to be something a person
    /// chose, so an absent or unreadable setting is the strict one.
    func test_unsetAndUnrecognizedBothResolveToToolsOnly() {
        XCTAssertEqual(AgentPermissionMode.resolved(fromRawValue: nil), .toolsOnly)
        XCTAssertEqual(AgentPermissionMode.resolved(fromRawValue: "yolo"), .toolsOnly)
        XCTAssertEqual(AgentPermissionMode.resolved(fromRawValue: ""), .toolsOnly)
    }

    func test_readsEveryMode() {
        XCTAssertEqual(AgentPermissionMode.resolved(fromRawValue: "tools"), .toolsOnly)
        XCTAssertEqual(AgentPermissionMode.resolved(fromRawValue: "edits"), .edits)
        XCTAssertEqual(AgentPermissionMode.resolved(fromRawValue: "ALL"), .everything)
    }

    /// Puck's own tools carry their own approval gate. Asking again here
    /// would mean two prompts for one action, in every mode.
    func test_puckOwnToolsAreAllowedInEveryMode() {
        let mcp = AcpPermissionRequest(raw: .object([
            "toolCall": .object(["title": .string("mcp__puck__run_shell")]),
        ]))
        for mode in AgentPermissionMode.allCases {
            XCTAssertTrue(mode.allows(mcp, ownMCPServer: server), "\(mode) refused Puck's own tool")
        }
    }

    func test_toolsOnlyRefusesWhateverTheCLIWantsToDoItself() {
        XCTAssertFalse(AgentPermissionMode.toolsOnly.allows(request(kind: "edit"), ownMCPServer: server))
        XCTAssertFalse(AgentPermissionMode.toolsOnly.allows(request(kind: "execute"), ownMCPServer: server))
    }

    func test_editsAllowsAnEditAndStillRefusesACommand() {
        XCTAssertTrue(AgentPermissionMode.edits.allows(request(kind: "edit"), ownMCPServer: server))
        XCTAssertFalse(AgentPermissionMode.edits.allows(request(kind: "execute"), ownMCPServer: server))
    }

    /// An agent that does not classify its calls must not have them read as
    /// edits: guessing wrong here writes to a file nobody approved.
    func test_editsRefusesACallTheAgentDidNotClassify() {
        XCTAssertFalse(AgentPermissionMode.edits.allows(request(kind: nil), ownMCPServer: server))
    }

    func test_everythingAllowsBoth() {
        XCTAssertTrue(AgentPermissionMode.everything.allows(request(kind: "edit"), ownMCPServer: server))
        XCTAssertTrue(AgentPermissionMode.everything.allows(request(kind: "execute"), ownMCPServer: server))
        XCTAssertTrue(AgentPermissionMode.everything.allows(request(kind: nil), ownMCPServer: server))
    }

    func test_readsTheModeFromTheEnvironment() {
        XCTAssertEqual(
            AgentConfiguration.permissionMode(environment: ["AGENT_PERMISSIONS": "edits"], searchPaths: []),
            .edits
        )
        XCTAssertEqual(AgentConfiguration.permissionMode(environment: [:], searchPaths: []), .toolsOnly)
    }
}

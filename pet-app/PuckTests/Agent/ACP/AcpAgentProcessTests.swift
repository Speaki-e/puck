//
//  AcpAgentProcessTests.swift
//  PuckTests
//
//  Two halves: the pure command resolution (always runs), and one integration
//  test that spawns the *real* vendored agent under the *real* node. The
//  integration test is what proves scripts/vendor-acp.sh produced something
//  that actually speaks ACP -- the scripted tests in
//  AcpCodeEditorSessionTests cannot, since they never leave the process.
//

import XCTest
@testable import Puck

final class AcpAgentCommandResolverTests: XCTestCase {
    func testNodeIsTakenFromPathBeforeAnyWellKnownLocation() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/custom/bin:/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0 == "/custom/bin/node" || $0 == "/opt/homebrew/bin/node" },
            nvmVersions: { _ in [] }
        )

        XCTAssertEqual(found?.path, "/custom/bin/node")
    }

    func testHomebrewIsTriedWhenPathHasNoNode() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0 == "/opt/homebrew/bin/node" },
            nvmVersions: { _ in [] }
        )

        XCTAssertEqual(found?.path, "/opt/homebrew/bin/node")
    }

    func testNvmFallsBackToItsNewestInstall() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0.hasPrefix("/Users/x/.nvm/versions/node/") },
            nvmVersions: { _ in ["v18.20.0", "v22.11.0", "v20.9.0"] }
        )

        XCTAssertEqual(found?.path, "/Users/x/.nvm/versions/node/v22.11.0/bin/node")
    }

    func testNoNodeAnywhereIsReportedRatherThanGuessed() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { _ in false },
            nvmVersions: { _ in [] }
        )

        XCTAssertNil(found)
    }

    func testMissingNodeFailsCommandBuilding() {
        XCTAssertThrowsError(
            try AcpAgentCommandResolver.command(
                for: .claude,
                scriptURL: URL(fileURLWithPath: "/x/acp-claude.mjs"),
                node: nil,
                codexCLI: nil
            )
        ) { XCTAssertEqual($0 as? AcpAgentCommandError, .nodeNotFound) }
    }

    func testMissingBundledScriptIsAPackagingErrorOfItsOwn() {
        XCTAssertThrowsError(
            try AcpAgentCommandResolver.command(
                for: .claude,
                scriptURL: nil,
                node: URL(fileURLWithPath: "/usr/bin/node"),
                codexCLI: nil
            )
        ) { XCTAssertEqual($0 as? AcpAgentCommandError, .agentScriptMissing(.claude)) }
    }

    func testClaudeRunsTheBundledScriptUnderNode() throws {
        let command = try AcpAgentCommandResolver.command(
            for: .claude,
            scriptURL: URL(fileURLWithPath: "/x/acp-claude.mjs"),
            node: URL(fileURLWithPath: "/usr/bin/node"),
            codexCLI: nil
        )

        XCTAssertEqual(command.executable.path, "/usr/bin/node")
        XCTAssertEqual(command.arguments, ["/x/acp-claude.mjs"])
        XCTAssertTrue(command.extraEnvironment.isEmpty, "claude is self-contained; nothing to point it at")
    }

    func testCodexIsPointedAtTheUsersOwnCLI() throws {
        let command = try AcpAgentCommandResolver.command(
            for: .codex,
            scriptURL: URL(fileURLWithPath: "/x/acp-codex.mjs"),
            node: URL(fileURLWithPath: "/usr/bin/node"),
            codexCLI: URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        )

        // Without CODEX_PATH, codex-acp resolves @openai/codex out of a
        // node_modules tree that does not exist inside Puck.app.
        XCTAssertEqual(command.extraEnvironment["CODEX_PATH"], "/opt/homebrew/bin/codex")
    }

    func testCodexWithoutItsCLIIsRefusedRatherThanSpawnedToFail() {
        XCTAssertThrowsError(
            try AcpAgentCommandResolver.command(
                for: .codex,
                scriptURL: URL(fileURLWithPath: "/x/acp-codex.mjs"),
                node: URL(fileURLWithPath: "/usr/bin/node"),
                codexCLI: nil
            )
        ) { XCTAssertEqual($0 as? AcpAgentCommandError, .codexCLINotFound) }
    }

    func testEachAgentNamesADistinctBundledScript() {
        let names = Set(CodingAgentKind.allCases.map(\.bundledScriptName))
        XCTAssertEqual(names.count, CodingAgentKind.allCases.count)
    }

    func testOnlyTheSelectedAgentsCredentialsAreNamed() {
        XCTAssertEqual(CodingAgentKind.claude.apiKeyEnvironmentVariables, ["ANTHROPIC_API_KEY"])
        XCTAssertEqual(CodingAgentKind.codex.apiKeyEnvironmentVariables, ["CODEX_API_KEY", "OPENAI_API_KEY"])
    }
}

/// Spawns the real thing. Skips rather than fails when node is missing -- a
/// machine without node is a supported configuration (code_editor is simply
/// unavailable there), so this must not turn into a red suite.
final class AcpAgentProcessIntegrationTests: XCTestCase {
    func testTheVendoredClaudeAgentCompletesTheHandshake() async throws {
        guard let node = AcpAgentCommandResolver.resolveNode() else {
            throw XCTSkip("no node on this machine; code_editor is unavailable here by design")
        }
        guard let script = AcpAgentCommandResolver.bundledScriptURL(for: .claude, in: Bundle(for: Self.self))
            ?? AcpAgentCommandResolver.bundledScriptURL(for: .claude) else {
            return XCTFail("acp-claude.mjs is not in the bundle -- run scripts/vendor-acp.sh")
        }

        let command = try AcpAgentCommandResolver.command(
            for: .claude, scriptURL: script, node: node, codexCLI: nil
        )
        let agent = AcpAgentProcess(
            command: command,
            projectPath: NSTemporaryDirectory(),
            // No key: `initialize` is answered before any credential is needed,
            // which is exactly the part worth testing without one.
            credentials: [:]
        )
        try agent.start()
        defer { agent.kill() }

        let result = try await agent.connection.request(
            method: AcpMethod.initialize,
            params: .object([
                "protocolVersion": .number(Double(acpProtocolVersion)),
                "clientCapabilities": .object([:]),
            ])
        )

        XCTAssertEqual(result["protocolVersion"]?.numberValue, Double(acpProtocolVersion))
        XCTAssertEqual(result["agentInfo"]?["name"]?.stringValue, "@agentclientprotocol/claude-agent-acp")
    }
}

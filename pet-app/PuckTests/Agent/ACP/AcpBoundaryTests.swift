//
//  AcpBoundaryTests.swift
//  PuckTests
//
//  Ported from byeolki's workspace-side check (9c956c08) before that app was
//  deleted -- the Swift ACP port had no equivalent, and the two branches did
//  the same Electron removal in parallel.
//
//  Detection, not containment: the ACP child has no OS sandbox, so this reads
//  the locations it voluntarily reports and flags the write-shaped ones that
//  land outside the project. These tests pin down which updates count.
//

import XCTest
@testable import Puck

final class AcpBoundaryTests: XCTestCase {
    private let root = "/Users/x/project"

    private func update(kind: String, sessionUpdate: String = "tool_call", paths: [String]) -> AcpSessionUpdate {
        AcpSessionUpdate(raw: .object([
            "sessionId": .string("s-1"),
            "update": .object([
                "sessionUpdate": .string(sessionUpdate),
                "kind": .string(kind),
                "locations": .array(paths.map { .object(["path": .string($0)]) }),
            ]),
        ]))
    }

    func testAWriteInsideTheProjectIsNotFlagged() {
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["/Users/x/project/src/main.swift"])
        )

        XCTAssertTrue(flagged.isEmpty)
    }

    func testAWriteOutsideTheProjectIsFlagged() {
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["/Users/x/.ssh/authorized_keys"])
        )

        XCTAssertEqual(flagged, ["/Users/x/.ssh/authorized_keys"])
    }

    func testATraversalOutOfTheProjectIsResolvedBeforeComparing() {
        // The path is nominally under the root; only after standardizing is it
        // outside. Comparing the raw string would pass it.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "delete", paths: ["/Users/x/project/../../etc/hosts"])
        )

        // /Users/x/project/../.. is /Users, so the traversal lands on
        // /Users/etc/hosts -- outside the project either way, which is the point.
        XCTAssertEqual(flagged, ["/Users/etc/hosts"])
    }

    func testASiblingDirectorySharingThePrefixIsOutside() {
        // /Users/x/project-secrets starts with the root's characters but is
        // not inside it -- the classic prefix-match bug.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["/Users/x/project-secrets/key.txt"])
        )

        XCTAssertEqual(flagged, ["/Users/x/project-secrets/key.txt"])
    }

    func testReadShapedOperationsAreNotFlagged() {
        // Reading outside the project is not what this looks for; only
        // operations that change the filesystem.
        for kind in ["read", "search", "execute", "think", "fetch"] {
            XCTAssertTrue(
                AcpEventMapping.writesOutside(root: root, in: update(kind: kind, paths: ["/etc/passwd"])).isEmpty,
                "\(kind) should not be flagged"
            )
        }
    }

    func testEveryWriteShapedKindIsChecked() {
        for kind in ["edit", "delete", "move"] {
            XCTAssertEqual(
                AcpEventMapping.writesOutside(root: root, in: update(kind: kind, paths: ["/tmp/elsewhere"])),
                ["/tmp/elsewhere"],
                "\(kind) should be flagged"
            )
        }
    }

    func testToolCallUpdatesAreCheckedToolNotJustTheInitialCall() {
        // An agent reports the location it settled on in the update, not
        // always in the first call.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", sessionUpdate: "tool_call_update", paths: ["/tmp/elsewhere"])
        )

        XCTAssertEqual(flagged, ["/tmp/elsewhere"])
    }

    func testAnUpdateWithNoLocationsIsQuiet() {
        XCTAssertTrue(AcpEventMapping.writesOutside(root: root, in: update(kind: "edit", paths: [])).isEmpty)
    }

    func testMessageChunksAreNotBoundaryEvents() {
        let chunk = AcpSessionUpdate(raw: .object([
            "update": .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string("/etc/passwd")]),
            ]),
        ]))

        XCTAssertTrue(AcpEventMapping.writesOutside(root: root, in: chunk).isEmpty)
    }
}

/// The child environment (2026-08-16). Deliberately minimal -- an ACP child
/// should not inherit every secret this process happens to hold -- but it was
/// trimmed past what the vendor CLIs need, and the symptom pointed the wrong
/// way: a logged-in `claude` reported "Not logged in", which arrived as ACP
/// error -32000 "Authentication required" and read like a missing API key.
final class AcpAgentEnvironmentTests: XCTestCase {
    private func environment(kind: CodingAgentKind = .claude, credentials: [String: String] = [:]) -> [String: String] {
        let process = AcpAgentProcess(
            command: AcpAgentCommand(
                executable: URL(fileURLWithPath: "/usr/bin/node"),
                arguments: ["/x/agent.mjs"],
                extraEnvironment: [kind.vendorCLIEnvironmentVariable: "/usr/local/bin/\(kind.vendorCLIName)"]
            ),
            projectPath: NSTemporaryDirectory(),
            credentials: credentials
        )
        return process.childEnvironment
    }

    func testUSERIsPassedSoTheVendorCLICanFindItsKeychainLogin() {
        XCTAssertEqual(environment()["USER"], NSUserName())
    }

    func testTheBasicsTheAgentNeedsToRunAtAllArePassed() {
        let environment = environment()
        XCTAssertNotNil(environment["PATH"])
        XCTAssertNotNil(environment["HOME"], "the agents write scratch state under HOME")
        XCTAssertEqual(environment["NODE_ENV"], "production")
    }

    func testTheVendorCLIPathIsPassed() {
        XCTAssertEqual(environment()["CLAUDE_CODE_EXECUTABLE"], "/usr/local/bin/claude")
    }

    func testOnlyTheSelectedAgentsCredentialsAreForwarded() {
        let environment = environment(credentials: ["ANTHROPIC_API_KEY": "sk-test"])

        XCTAssertEqual(environment["ANTHROPIC_API_KEY"], "sk-test")
        // The parent's whole environment is not handed over -- a subprocess
        // has no business seeing every secret this process happens to hold.
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["AWS_SECRET_ACCESS_KEY"])
    }
}

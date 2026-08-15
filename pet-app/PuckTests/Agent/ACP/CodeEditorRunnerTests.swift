//
//  CodeEditorRunnerTests.swift
//  PuckTests
//
//  Ports the queue and cancellation cases from
//  workspace/src/agent-host/code-editor-queue.test.ts, against a scripted
//  agent rather than a spawned one -- proving that two runs on one workspace
//  serialise does not need a real node.
//

import XCTest
@testable import Puck

/// A transport that answers the handshake and holds `session/prompt` open
/// until the test releases it, so overlap is observable.
private final class FakeAgent: AcpAgentTransport {
    let connection: AcpConnection
    private(set) var isRunning = true
    private(set) var terminateCount = 0
    private(set) var killCount = 0
    /// Set by the test to observe ordering.
    var onPrompt: (() -> Void)?
    private var release: CheckedContinuation<Void, Never>?
    private let holdsPrompt: Bool
    private var promptID: JSONValue?

    init(holdsPrompt: Bool = false) {
        self.holdsPrompt = holdsPrompt
        var deliver: ((JSONValue) -> Void)!
        let connection = AcpConnection(send: { data in
            guard let frame = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
            deliver(frame)
        })
        self.connection = connection
        deliver = { [weak self] frame in
            guard let self, let method = frame["method"]?.stringValue, let id = frame["id"] else { return }
            switch method {
            case "initialize":
                self.reply(id: id, result: .object(["protocolVersion": .number(1)]))
            case "session/new":
                self.reply(id: id, result: .object(["sessionId": .string("s-1")]))
            case "session/prompt":
                self.onPrompt?()
                if self.holdsPrompt {
                    self.promptID = id
                } else {
                    self.reply(id: id, result: .object(["stopReason": .string("end_turn")]))
                }
            default:
                break
            }
        }
    }

    private func reply(id: JSONValue, result: JSONValue) {
        var data = try! JSONEncoder().encode(
            JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "result": result])
        )
        data.append(UInt8(ascii: "\n"))
        connection.receive(data)
    }

    /// Lets a held prompt finish.
    func finishPrompt(stopReason: String = "end_turn") {
        guard let promptID else { return }
        self.promptID = nil
        reply(id: promptID, result: .object(["stopReason": .string(stopReason)]))
    }

    func terminate() { terminateCount += 1; isRunning = false }
    func kill() { killCount += 1; isRunning = false }
}

private func makeEnvironment(
    agent: @escaping (CodingAgentKind, String) throws -> AcpAgentTransport,
    kind: CodingAgentKind = .claude
) -> CodeEditorRunnerEnvironment {
    CodeEditorRunnerEnvironment(
        startAgent: agent,
        credentials: { _ in [:] },
        codingAgent: { kind }
    )
}

final class CodeEditorRunnerTests: XCTestCase {
    private var project: URL!

    override func setUpWithError() throws {
        project = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CodeEditorRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: project)
    }

    // MARK: - Happy path

    func testASingleRunCompletes() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in FakeAgent() }))

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        XCTAssertTrue(result.ok)
    }

    func testTheAgentProcessIsTerminatedWhenTheRunEnds() async {
        let agent = FakeAgent()
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in agent }))

        _ = await runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go")

        XCTAssertEqual(agent.terminateCount, 1, "an agent left running would outlive the app's interest in it")
    }

    func testADuplicateRequestIdIsRefused() async {
        let held = FakeAgent(holdsPrompt: true)
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in held }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        let second = await runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "b")

        XCTAssertEqual(second.error, "duplicate_request")
        held.finishPrompt()
        _ = await first
    }

    // MARK: - Queueing

    func testTwoRunsOnOneWorkspaceDoNotOverlap() async {
        let firstAgent = FakeAgent(holdsPrompt: true)
        let secondAgent = FakeAgent()
        var order: [String] = []
        firstAgent.onPrompt = { order.append("first-started") }
        secondAgent.onPrompt = { order.append("second-started") }
        var handed = 0
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            handed += 1
            return handed == 1 ? firstAgent : secondAgent
        }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 150_000_000)
        async let second = runner.run(requestId: "r2", workspaceId: "w1", projectPath: project.path, task: "b")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(order, ["first-started"], "the second run must not start while the first holds the workspace")

        firstAgent.finishPrompt()
        _ = await first
        _ = await second
        XCTAssertEqual(order, ["first-started", "second-started"])
    }

    func testDifferentWorkspacesRunInParallel() async {
        let firstAgent = FakeAgent(holdsPrompt: true)
        let secondAgent = FakeAgent()
        var order: [String] = []
        firstAgent.onPrompt = { order.append("first-started") }
        secondAgent.onPrompt = { order.append("second-started") }
        var handed = 0
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            handed += 1
            return handed == 1 ? firstAgent : secondAgent
        }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 150_000_000)
        let second = await runner.run(requestId: "r2", workspaceId: "w2", projectPath: project.path, task: "b")
        XCTAssertTrue(second.ok, "a different workspace has nothing to contend over")
        XCTAssertEqual(order, ["first-started", "second-started"])

        firstAgent.finishPrompt()
        _ = await first
    }

    // MARK: - Cancellation

    func testCancellingAQueuedRunNeverStartsAnAgent() async {
        let firstAgent = FakeAgent(holdsPrompt: true)
        var handed = 0
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            handed += 1
            return handed == 1 ? firstAgent : FakeAgent()
        }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 150_000_000)
        async let second = runner.run(requestId: "r2", workspaceId: "w1", projectPath: project.path, task: "b")
        try? await Task.sleep(nanoseconds: 100_000_000)
        let cancelled = await runner.cancel(requestId: "r2")

        XCTAssertTrue(cancelled)
        firstAgent.finishPrompt()
        _ = await first
        let secondResult = await second
        XCTAssertEqual(secondResult.error, "cancelled")
        XCTAssertEqual(handed, 1, "the cancelled run should never have been handed an agent")
    }

    func testCancellingAnUnknownRequestReportsSo() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in FakeAgent() }))

        let cancelled = await runner.cancel(requestId: "nope")

        XCTAssertFalse(cancelled)
    }

    // MARK: - Unavailable agent

    func testAMissingNodeIsReportedAsAToolResultRatherThanACrash() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            throw AcpAgentCommandError.nodeNotFound
        }))

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "agent_unavailable")
        XCTAssertTrue(result.summary.contains("Node.js"))
    }

    func testAMissingVendorCLINamesTheOneToInstall() async {
        for kind in CodingAgentKind.allCases {
            let runner = CodeEditorRunner(environment: makeEnvironment(
                agent: { _, _ in throw AcpAgentCommandError.vendorCLINotFound(kind) },
                kind: kind
            ))

            let result = await runner.run(
                requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
            )

            XCTAssertFalse(result.ok)
            XCTAssertTrue(
                result.summary.contains(kind.vendorCLIName),
                "the message has to name the missing CLI, not just say something failed"
            )
        }
    }

    // MARK: - Changed files

    func testFilesWrittenDuringTheRunAreReported() async {
        let agent = FakeAgent(holdsPrompt: true)
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in agent }))
        agent.onPrompt = { [project] in
            try? Data("edited".utf8).write(to: project!.appendingPathComponent("edited.txt"))
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { agent.finishPrompt() }
        }

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        XCTAssertEqual(result.changedFiles, ["edited.txt"])
    }
}

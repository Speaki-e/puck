//
//  AcpCodeEditorSessionTests.swift
//  PuckTests
//
//  Drives a whole code_editor turn against a scripted NDJSON stream -- the
//  Swift counterpart of workspace/src/agent-host/acp-adapter.test.ts, minus
//  the parts that were really testing Node's spawn.
//

import XCTest
@testable import Puck

/// Stands in for the agent process: collects what the client wrote and feeds
/// back whatever the test scripts, line by line.
private final class ScriptedAgent {
    private(set) var written: [JSONValue] = []
    var connection: AcpConnection!
    /// Answers a request by method name. Returning nil means "stay silent",
    /// which is how the tests exercise a hang.
    var replies: [String: (JSONValue) -> JSONValue?] = [:]
    /// Answers a request with a JSON-RPC error instead of a result.
    var errorReplies: [String: (code: Int, message: String)] = [:]

    init() {
        connection = AcpConnection(send: { [weak self] data in
            guard let self,
                  let frame = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return }
            self.written.append(frame)
            guard let method = frame["method"]?.stringValue, let id = frame["id"] else { return }
            if let failure = self.errorReplies[method] {
                self.push(.object([
                    "jsonrpc": .string("2.0"),
                    "id": id,
                    "error": .object([
                        "code": .number(Double(failure.code)),
                        "message": .string(failure.message),
                    ]),
                ]))
                return
            }
            guard let reply = self.replies[method]?(frame["params"] ?? .null) else { return }
            self.push(.object(["jsonrpc": .string("2.0"), "id": id, "result": reply]))
        })
    }

    /// Delivers one NDJSON line to the client.
    func push(_ value: JSONValue) {
        guard var data = try? JSONEncoder().encode(value) else { return }
        data.append(UInt8(ascii: "\n"))
        connection.receive(data)
    }

    func pushRaw(_ line: String) {
        connection.receive(Data((line + "\n").utf8))
    }

    func methodsWritten() -> [String] {
        written.compactMap { $0["method"]?.stringValue }
    }

    func params(forMethod method: String) -> JSONValue? {
        written.first { $0["method"]?.stringValue == method }?["params"]
    }

    /// The happy path every test needs before it gets to the interesting part.
    func stubHandshake(stopReason: String = "end_turn") {
        replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        replies["session/prompt"] = { _ in .object(["stopReason": .string(stopReason)]) }
    }
}

private func textChunk(_ text: String) -> JSONValue {
    .object([
        "jsonrpc": .string("2.0"),
        "method": .string("session/update"),
        "params": .object([
            "sessionId": .string("s-1"),
            "update": .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string(text)]),
            ]),
        ]),
    ])
}

final class AcpCodeEditorSessionTests: XCTestCase {
    // MARK: - Handshake

    func testRunsTheFullHandshakeInOrder() async {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session.run(task: "fix it")

        XCTAssertTrue(result.ok)
        XCTAssertEqual(agent.methodsWritten(), ["initialize", "session/new", "session/prompt"])
    }

    func testSessionIsOpenedOnTheProjectDirectory() async {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        _ = await session.run(task: "fix it")

        XCTAssertEqual(agent.params(forMethod: "session/new")?["cwd"]?.stringValue, "/tmp/project")
    }

    func testTheTaskIsSentAsThePrompt() async {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        _ = await session.run(task: "rename the function")

        let prompt = agent.params(forMethod: "session/prompt")?["prompt"]?.arrayValue?.first
        XCTAssertEqual(prompt?["text"]?.stringValue, "rename the function")
    }

    func testAMissingSessionIdIsAFailureRatherThanAHang() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object([:]) }
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session.run(task: "fix it")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "acp_error")
    }

    // MARK: - Streaming

    func testMessageChunksAccumulateIntoTheSummary() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(textChunk("함수 이름을 "))
            agent?.push(textChunk("바꿨습니다."))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session.run(task: "rename")

        XCTAssertEqual(result.summary, "함수 이름을 바꿨습니다.")
    }

    func testUpdatesAreForwardedForTheTranscript() async {
        let agent = ScriptedAgent()
        var forwarded: [AcpSessionUpdate] = []
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(textChunk("작업 중"))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpCodeEditorSession(
            connection: agent.connection,
            projectPath: "/tmp/project",
            onUpdate: { forwarded.append($0) }
        )

        _ = await session.run(task: "go")

        XCTAssertEqual(forwarded.count, 1)
        XCTAssertEqual(forwarded.first?.kind, .agentMessageChunk)
        XCTAssertEqual(forwarded.first?.text, "작업 중")
    }

    func testAnEmptySummaryFallsBackToTheStopReason() async {
        let agent = ScriptedAgent()
        agent.stubHandshake(stopReason: "max_tokens")
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session.run(task: "go")

        XCTAssertEqual(result.summary, "ACP 작업 완료 (max_tokens)")
    }

    func testAMalformedLineIsSkippedRatherThanEndingTheRun() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.pushRaw("this is not json")
            agent?.push(textChunk("계속 진행"))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session.run(task: "go")

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.summary, "계속 진행")
    }

    // MARK: - Permission

    func testAnApprovedPermissionSelectsTheAllowOption() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(.object([
                "jsonrpc": .string("2.0"),
                "id": .number(99),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("s-1"),
                    "options": .array([
                        .object(["optionId": .string("no"), "name": .string("거부"), "kind": .string("reject_once")]),
                        .object(["optionId": .string("yes"), "name": .string("허용"), "kind": .string("allow_once")]),
                    ]),
                ]),
            ]))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpCodeEditorSession(
            connection: agent.connection,
            projectPath: "/tmp/project",
            resolvePermission: { _ in true }
        )

        _ = await session.run(task: "go")
        // The answer is written asynchronously from the request handler.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let answer = agent.written.first { $0["id"]?.numberValue == 99 }
        XCTAssertEqual(answer?["result"]?["outcome"]?["optionId"]?.stringValue, "yes")
    }

    func testADeniedPermissionSelectsTheRejectOption() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(.object([
                "jsonrpc": .string("2.0"),
                "id": .number(99),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("s-1"),
                    "options": .array([
                        .object(["optionId": .string("no"), "name": .string("거부"), "kind": .string("reject_once")]),
                        .object(["optionId": .string("yes"), "name": .string("허용"), "kind": .string("allow_once")]),
                    ]),
                ]),
            ]))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpCodeEditorSession(
            connection: agent.connection,
            projectPath: "/tmp/project",
            resolvePermission: { _ in false }
        )

        _ = await session.run(task: "go")
        try? await Task.sleep(nanoseconds: 100_000_000)

        let answer = agent.written.first { $0["id"]?.numberValue == 99 }
        XCTAssertEqual(answer?["result"]?["outcome"]?["optionId"]?.stringValue, "no")
    }

    func testAnUnknownAgentRequestIsAnsweredRatherThanLeftHanging() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(.object([
                "jsonrpc": .string("2.0"),
                "id": .number(7),
                "method": .string("fs/read_text_file"),
                "params": .object([:]),
            ]))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        _ = await session.run(task: "go")

        XCTAssertNotNil(
            agent.written.first { $0["id"]?.numberValue == 7 },
            "an unanswered request would stall the agent for the whole 600s tool timeout"
        )
    }

    // MARK: - Cancellation

    func testCancelNotifiesTheAgentWithItsSessionId() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        var session: AcpCodeEditorSession?
        agent.replies["session/prompt"] = { _ in
            session?.cancel()
            return .object(["stopReason": .string("cancelled")])
        }
        session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session!.run(task: "go")

        XCTAssertEqual(result, .cancelled())
        XCTAssertEqual(agent.params(forMethod: "session/cancel")?["sessionId"]?.stringValue, "s-1")
    }

    func testAProcessThatDiesMidRunReportsItsStderr() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        // No reply to session/prompt; the process "exits" instead.
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        async let outcome = session.run(task: "go")
        try? await Task.sleep(nanoseconds: 100_000_000)
        agent.connection.failAllPending(with: AcpError.processExited(detail: "ENOENT: node not found"))
        let result = await outcome

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "acp_error")
        XCTAssertEqual(result.detail, "ENOENT: node not found")
    }

    // MARK: - Failure detail

    /// The classic case: `-32000 Authentication required`, whose actual
    /// explanation ("Not logged in") the vendor CLI wrote to stderr. Without
    /// the tail the message names a symptom and nothing that leads to a cause.
    func testAnAcpErrorCarriesTheStderrTailThatExplainsIt() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.errorReplies["session/prompt"] = (code: -32000, message: "Authentication required")
        let session = AcpCodeEditorSession(
            connection: agent.connection,
            projectPath: "/tmp/project",
            stderrTail: { "  claude: Not logged in. Run `claude login`.\n" }
        )

        let result = await session.run(task: "go")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.detail,
            "ACP error -32000: Authentication required\nclaude: Not logged in. Run `claude login`."
        )
    }

    func testAnAcpErrorWithNoStderrIsReportedOnItsOwn() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.errorReplies["session/prompt"] = (code: -32000, message: "Authentication required")
        let session = AcpCodeEditorSession(connection: agent.connection, projectPath: "/tmp/project")

        let result = await session.run(task: "go")

        XCTAssertEqual(result.detail, "ACP error -32000: Authentication required")
    }

    /// The exited case already reports the tail; it must not be pasted twice.
    func testAProcessExitDoesNotRepeatTheStderrTail() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        let session = AcpCodeEditorSession(
            connection: agent.connection,
            projectPath: "/tmp/project",
            stderrTail: { "boom" }
        )

        async let outcome = session.run(task: "go")
        try? await Task.sleep(nanoseconds: 100_000_000)
        agent.connection.failAllPending(with: AcpError.processExited(detail: "boom"))
        let result = await outcome

        XCTAssertEqual(result.detail, "boom")
    }

    // MARK: - reportedDetail

    /// `detail ?? summary` never chose the summary -- `detail` is set on every
    /// failing path -- so the sentence written for the user ("… CLI를 찾을 수
    /// 없습니다") never reached the model or the transcript, which saw only
    /// `vendorCLINotFound(Puck.CodingAgentKind.claude)`.
    func testAFailureReportsTheUserFacingSummaryBeforeTheTechnicalDetail() {
        let result = CodeEditorResult(
            ok: false,
            summary: "claude CLI를 찾을 수 없습니다. 설치한 뒤 다시 시도해 주세요.",
            changedFiles: [],
            error: "agent_unavailable",
            detail: "vendorCLINotFound(Puck.CodingAgentKind.claude)"
        )

        XCTAssertEqual(
            result.reportedDetail,
            "claude CLI를 찾을 수 없습니다. 설치한 뒤 다시 시도해 주세요.\nvendorCLINotFound(Puck.CodingAgentKind.claude)"
        )
    }

    func testAFailureWithNoTechnicalDetailStillReportsItsSummary() {
        let result = CodeEditorResult(
            ok: false, summary: "코딩 에이전트를 시작하지 못했습니다.", changedFiles: [],
            error: "agent_unavailable", detail: nil
        )

        XCTAssertEqual(result.reportedDetail, "코딩 에이전트를 시작하지 못했습니다.")
    }

    /// A success's summary is the answer itself and already travels as `data`;
    /// repeating it in `detail` would show the whole reply twice.
    func testASuccessReportsOnlyItsOwnDetail() {
        let result = CodeEditorResult(ok: true, summary: "고쳤어요", changedFiles: [])

        XCTAssertNil(result.reportedDetail)
    }
}

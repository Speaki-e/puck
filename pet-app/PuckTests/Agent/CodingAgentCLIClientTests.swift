//
//  CodingAgentCLIClientTests.swift
//  PuckTests
//
//  The CLI-backed conversation provider: one ACP turn in, one text-only
//  GPTTurn out. Driven against a scripted NDJSON stream, so none of this
//  spawns node or needs a vendor CLI installed.
//

import XCTest
@testable import Puck

/// An AcpAgentTransport over a scripted connection, tracking the teardown the
/// client is supposed to perform.
private final class FakeTransport: AcpAgentTransport {
    let connection: AcpConnection
    private(set) var terminateCount = 0
    private(set) var killCount = 0
    var isRunning = true
    var stderr = ""

    init(connection: AcpConnection) {
        self.connection = connection
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func kill() { killCount += 1 }

    func currentStderrTail() -> String { stderr }
}

private func agentTextChunk(_ text: String) -> JSONValue {
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

/// The CLI provider as `AgentConfiguration` resolves it: no key, no model.
/// Which CLI is not part of this -- `codingAgent` reads `CODING_AGENT` from
/// the environment, deliberately the same setting `code_editor` reads -- and
/// these tests inject `startAgent` instead, so the kind never matters here.
private func cliConfiguration() -> AgentConfiguration {
    AgentConfiguration(apiKey: nil, model: "", provider: .cli, keySource: nil)
}

final class CodingAgentCLIClientTests: XCTestCase {

    // MARK: - The happy path

    func test_send_returnsTheAgentsTextAsATextOnlyTurn() async throws {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("안녕하세요!"))
            return .object(["stopReason": .string("end_turn")])
        }
        let transport = FakeTransport(connection: agent.connection)
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in transport }
        )

        let turn = try await client.send(messages: [.user("안녕")], tools: [])

        XCTAssertEqual(turn.text, "안녕하세요!")
        XCTAssertTrue(turn.toolCalls.isEmpty)
    }

    /// The host's tools are handed over on every send and cannot be honoured
    /// here -- ACP has no tool-call channel back to us. A turn that quietly
    /// claimed one would be the model narrating an action nothing performed.
    func test_send_neverReturnsToolCalls_evenWhenToolsAreOffered() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        let turn = try await client.send(
            messages: [.user("날씨 앱 켜줘")],
            tools: [GPTToolSpec(name: "launch_app", description: "launch", parameters: [])]
        )

        XCTAssertTrue(turn.toolCalls.isEmpty)
    }

    func test_send_opensTheSessionOnTheWorkingDirectory() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("확인했어요."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            workingDirectory: { "/tmp/some-project" },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.user("여기 뭐 있어?")], tools: [])

        XCTAssertEqual(agent.params(forMethod: "session/new")?["cwd"]?.stringValue, "/tmp/some-project")
    }

    /// A child left behind is a node process plus the vendor's ~256MB binary
    /// with nothing on screen to point at it, and a chat turn happens far more
    /// often than a code edit does.
    func test_send_endsTheAgentProcessWhenTheTurnIsDone() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("끝."))
            return .object(["stopReason": .string("end_turn")])
        }
        let transport = FakeTransport(connection: agent.connection)
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in transport }
        )

        _ = try await client.send(messages: [.user("hi")], tools: [])
        // Teardown is detached so the answer does not wait on a child's exit.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(transport.terminateCount, 1)
    }

    // MARK: - Failures

    /// codex is not installed on every machine (and is not installed on the
    /// one this was written on). Nothing was spawned, so there is nothing to
    /// wait on: it has to fail immediately, with the same sentence
    /// code_editor uses, rather than hang until a timeout.
    func test_send_reportsAMissingVendorCLIImmediately() async {
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in throw AcpAgentCommandError.vendorCLINotFound(.codex) }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("a missing CLI must fail the turn")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "codex CLI를 찾을 수 없습니다. 설치한 뒤 다시 시도해 주세요."
            )
        }
    }

    func test_send_reportsAMissingNodeInTermsOfWhatTheUserWasDoing() async {
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in throw AcpAgentCommandError.nodeNotFound }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("a missing node must fail the turn")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "대화에는 Node.js가 필요합니다. 설치 후 다시 시도해 주세요."
            )
        }
    }

    /// The classic: the CLI is installed but not logged in. The ACP error
    /// names a symptom; the stderr tail is the part that says what to do, so
    /// both have to reach the transcript.
    func test_send_reportsAnAcpErrorWithTheStderrThatExplainsIt() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.errorReplies["session/prompt"] = (code: -32000, message: "Authentication required")
        let transport = FakeTransport(connection: agent.connection)
        transport.stderr = "claude: Not logged in. Run `claude login`."
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in transport }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("an ACP error must fail the turn")
        } catch {
            let described = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(described.contains("Authentication required"), described)
            XCTAssertTrue(described.contains("claude login"), described)
        }
    }

    func test_send_reportsATurnThatSaidNothingRatherThanReturningAnEmptyReply() async {
        let agent = ScriptedAgent()
        agent.stubHandshake(stopReason: "max_tokens")
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        do {
            let turn = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("an empty turn must not become an empty assistant bubble: \(turn.text ?? "nil")")
        } catch {
            XCTAssertEqual(error as? CodingAgentCLIError, .emptyReply(stopReason: "max_tokens"))
        }
    }

    /// A child that is alive but wedged answers session/prompt never. Without
    /// a deadline the chat spins until the app is quit.
    func test_send_givesUpOnAnAgentThatNeverAnswers() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        // No reply to session/prompt at all.
        let transport = FakeTransport(connection: agent.connection)
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            timeoutSeconds: 0.2,
            startAgent: { _, _ in transport }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("a wedged agent must not hold the turn open")
        } catch {
            XCTAssertEqual(error as? CodingAgentCLIError, .timedOut(seconds: 0))
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(transport.terminateCount, 1, "the wedged child must be ended, not abandoned")
    }

    // MARK: - Prompt construction

    /// The whole point of the override: AgentRunner's system prompt tells the
    /// model to call point_at and code_editor, and on this provider it cannot.
    /// Whatever else changes, this text has to be in the prompt.
    func test_prompt_carriesTheToolUnavailabilityOverride() {
        let prompt = CodingAgentCLIClient.prompt(for: [.system("You are the brain of Puck."), .user("안녕")])

        XCTAssertTrue(prompt.contains(CodingAgentCLIClient.toolAvailabilityOverride))
    }

    /// After the system prompt it contradicts, not before: the later
    /// instruction is the one a model follows.
    func test_prompt_putsTheOverrideAfterTheSystemPromptItCorrects() throws {
        let prompt = CodingAgentCLIClient.prompt(for: [.system("Use point_at to show the user."), .user("안녕")])

        let system = try XCTUnwrap(prompt.range(of: "Use point_at to show the user."))
        let override = try XCTUnwrap(prompt.range(of: CodingAgentCLIClient.toolAvailabilityOverride))
        XCTAssertTrue(system.lowerBound < override.lowerBound)
    }

    func test_prompt_carriesEverySystemLine_includingTheWorkspaceContext() {
        let prompt = CodingAgentCLIClient.prompt(for: [
            .system("You are the brain of Puck."),
            .system("Current workspace: puck, bound to the project at /tmp/puck."),
            .user("여기 뭐 있어?"),
        ])

        XCTAssertTrue(prompt.contains("You are the brain of Puck."))
        XCTAssertTrue(prompt.contains("bound to the project at /tmp/puck"))
    }

    /// One prompt per turn carries the whole conversation: there is no live
    /// ACP session between turns holding it (see the client's header).
    func test_prompt_rendersTheWholeTranscriptInOrder() {
        let prompt = CodingAgentCLIClient.prompt(for: [
            .system("system"),
            .user("첫 질문"),
            .assistant(text: "첫 답변", toolCalls: []),
            .user("둘째 질문"),
        ])

        let first = prompt.range(of: "User: 첫 질문")
        let answer = prompt.range(of: "Assistant: 첫 답변")
        let second = prompt.range(of: "User: 둘째 질문")
        XCTAssertNotNil(first)
        XCTAssertNotNil(answer)
        XCTAssertNotNil(second)
        XCTAssertTrue(first!.lowerBound < answer!.lowerBound)
        XCTAssertTrue(answer!.lowerBound < second!.lowerBound)
    }

    /// A conversation can start on OpenAI, call launch_app, and then be
    /// continued here after a provider switch. Those turns are history, and
    /// dropping them would leave the CLI answering a question whose context
    /// it cannot see.
    func test_prompt_keepsToolCallsAndResultsFromTurnsTakenUnderAnotherProvider() {
        let prompt = CodingAgentCLIClient.prompt(for: [
            .system("system"),
            .user("날씨 앱 켜줘"),
            .assistant(text: nil, toolCalls: [
                GPTToolCall(id: "1", name: "launch_app", argumentsJSON: "{\"app_name\":\"Weather\"}"),
            ]),
            .tool(callId: "1", content: "{\"pid\":42}"),
            .user("켜졌어?"),
        ])

        XCTAssertTrue(prompt.contains("launch_app"))
        XCTAssertTrue(prompt.contains("{\"app_name\":\"Weather\"}"))
        XCTAssertTrue(prompt.contains("Tool result: {\"pid\":42}"))
    }

    func test_prompt_isSentAsTheAcpPromptText() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.system("system"), .user("고유한질문")], tools: [])

        let sent = agent.params(forMethod: "session/prompt")?["prompt"]?.arrayValue?.first?["text"]?.stringValue
        XCTAssertNotNil(sent)
        XCTAssertTrue(sent!.contains("User: 고유한질문"))
        XCTAssertTrue(sent!.contains(CodingAgentCLIClient.toolAvailabilityOverride))
    }
}

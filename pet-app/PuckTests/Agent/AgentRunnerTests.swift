//
//  AgentRunnerTests.swift
//  Puck
//
//  Covers AgentRunner.pathArgument, and one exercise of the turn loop itself
//  against a FakeLLMClient conforming to AgentLLMClient -- now that the loop
//  no longer requires the concrete GPTClient, network mocking is no longer
//  needed to construct a runner for a test.
//

import XCTest
@testable import Puck

final class AgentRunnerTests: XCTestCase {
    /// Conforms to AgentLLMClient only -- proves AgentRunner doesn't need the
    /// concrete GPTClient to run a turn.
    private final class FakeLLMClient: AgentLLMClient {
        var turns: [GPTTurn] = []
        private(set) var sendCount = 0

        func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
            sendCount += 1
            return turns.isEmpty ? GPTTurn(text: "done", toolCalls: []) : turns.removeFirst()
        }
    }

    /// Records what the model was actually shown, which is the only way to
    /// see one chat's context leaking into another.
    private final class RecordingLLMClient: AgentLLMClient {
        private(set) var lastMessages: [GPTMessage] = []
        /// Sleeps inside `send`, so a test can replace the run while it is
        /// where a real run spends nearly all its time.
        var stallNanoseconds: UInt64 = 0

        func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
            lastMessages = messages
            if stallNanoseconds > 0 { try? await Task.sleep(nanoseconds: stallNanoseconds) }
            return GPTTurn(text: "ok", toolCalls: [])
        }

        var lastUserTexts: [String] {
            lastMessages.compactMap { if case .user(let t) = $0 { return t } else { return nil } }
        }

        var lastSystemTexts: [String] {
            lastMessages.compactMap { if case .system(let t) = $0 { return t } else { return nil } }
        }
    }

    private func makeRecordingRunner() -> (AgentRunner, RecordingLLMClient) {
        let client = RecordingLLMClient()
        let runner = AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { _ in }
        )
        return (runner, client)
    }

    // MARK: - One conversation per chat

    /// The bug this exists for: every chat in the app shared one message
    /// stack, so a new chat opened with the previous one's conversation
    /// already in it -- including another workspace's "no project folder is
    /// bound to it, so there are no files to read or list", which the model
    /// then repeated at a chat whose workspace did have one.
    func test_aSecondChat_doesNotSeeTheFirstOnesMessages() async {
        let (runner, client) = makeRecordingRunner()

        runner.sessionId = "chat-1"
        await runner.run(command: "첫 대화의 질문")

        runner.sessionId = "chat-2"
        await runner.run(command: "두 번째 대화의 질문")

        XCTAssertEqual(client.lastUserTexts, ["두 번째 대화의 질문"])
    }

    /// The other half: going back to a chat has to bring its own history with
    /// it, or the model contradicts the transcript the user is looking at.
    func test_returningToAChat_stillHasItsOwnHistory() async {
        let (runner, client) = makeRecordingRunner()

        runner.sessionId = "chat-1"
        await runner.run(command: "첫 질문")
        runner.sessionId = "chat-2"
        await runner.run(command: "다른 대화")
        runner.sessionId = "chat-1"
        await runner.run(command: "이어서")

        XCTAssertEqual(client.lastUserTexts, ["첫 질문", "이어서"])
    }

    /// The workspace line is per chat too -- it was announced once per runner,
    /// so a chat opened later under a different workspace never heard about
    /// its own.
    func test_eachChatHearsItsOwnWorkspaceLine() async {
        let (runner, client) = makeRecordingRunner()

        runner.sessionId = "chat-1"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "기본 워크스페이스", projectPath: nil)
        await runner.run(command: "안녕")

        runner.sessionId = "chat-2"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "치ㅑ", projectPath: "/tmp/cli")
        await runner.run(command: "이 프로젝트 분석해줘")

        let systems = client.lastSystemTexts
        XCTAssertTrue(systems.contains { $0.contains("/tmp/cli") }, "got \(systems)")
        XCTAssertFalse(
            systems.contains { $0.contains("No project folder is bound") },
            "the other workspace's line must not be in this chat: \(systems)"
        )
    }

    /// Announced once per chat, not once per turn.
    func test_theWorkspaceLine_isNotRepeatedEveryTurn() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "chat-1"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "puck", projectPath: "/tmp/puck")

        await runner.run(command: "하나")
        await runner.run(command: "둘")

        XCTAssertEqual(client.lastSystemTexts.filter { $0.contains("/tmp/puck") }.count, 1)
    }

    /// A task session is a branch of the conversation that opened it, not a
    /// fresh one -- the agent has to remember what it was asked to do.
    func test_carryConversation_movesTheHistoryIntoTheTaskSession() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "casual"
        await runner.run(command: "이 버그 고쳐줘")

        runner.carryConversation(from: "casual", to: "task")
        runner.sessionId = "task"
        await runner.run(command: "계속")

        XCTAssertEqual(client.lastUserTexts, ["이 버그 고쳐줘", "계속"])
    }

    /// Deleting a chat has to take its conversation with it; otherwise the
    /// model keeps what the user just threw away.
    func test_forgetSession_dropsThatChatsConversation() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "chat-1"
        await runner.run(command: "지워질 이야기")

        runner.forgetSession("chat-1")
        await runner.run(command: "새 이야기")

        XCTAssertEqual(client.lastUserTexts, ["새 이야기"])
    }

    /// A run keeps executing after it is cancelled until it next checks, and
    /// `sessionId` by then belongs to whichever chat replaced it. The dying
    /// run's answer must not land there.
    func test_aCancelledRun_doesNotWriteIntoTheChatThatReplacedIt() async {
        let (runner, client) = makeRecordingRunner()
        client.stallNanoseconds = 200_000_000

        runner.sessionId = "chat-1"
        let first = Task { await runner.run(command: "느린 질문") }
        try? await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        runner.sessionId = "chat-2"
        await runner.run(command: "두 번째 대화의 질문")
        await first.value

        XCTAssertEqual(client.lastUserTexts, ["두 번째 대화의 질문"])
    }

    func test_agentRunner_acceptsAnyAgentLLMClient() async throws {
        let fake = FakeLLMClient()
        fake.turns = [GPTTurn(text: "안녕하세요", toolCalls: [])]
        var events: [BridgeEvent] = []

        let runner = AgentRunner(
            client: fake,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { events.append($0) }
        )

        await runner.run(command: "hi")

        XCTAssertEqual(fake.sendCount, 1)
        XCTAssertTrue(events.contains(.textChunk(text: "안녕하세요")))
        XCTAssertTrue(events.contains(.agentDone(ok: true, summary: "안녕하세요")))
    }

    /// Hangs inside the model call until the enclosing Task is cancelled,
    /// which is what a real 중지 during a slow completion looks like.
    private final class HangingLLMClient: AgentLLMClient {
        let started: XCTestExpectation

        init(started: XCTestExpectation) { self.started = started }

        func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
            started.fulfill()
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return GPTTurn(text: "answered after the stop", toolCalls: [])
        }
    }

    /// 중지 pressed while the model call is in flight. The run has to end, and
    /// it has to end as a stop rather than as the URLError(.cancelled) the
    /// cancelled request actually throws -- "요청이 취소되었습니다" in the
    /// transcript reads as a network failure the user didn't cause.
    func test_run_cancelledDuringTheModelCall_endsAsAStopNotAnError() async {
        let started = expectation(description: "model call in flight")
        let events = UncheckedBox([BridgeEvent]())
        let runner = AgentRunner(
            client: HangingLLMClient(started: started),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event in events.value.append(event) }
        )

        let task = Task { await runner.run(command: "천천히 해줘") }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await task.value

        let emitted = events.value
        XCTAssertEqual(
            emitted.last,
            .agentDone(ok: false, summary: AgentRunner.cancelledSummary),
            "a cancelled run still has to finish, or the chat spins forever"
        )
        XCTAssertTrue(emitted.contains(.textChunk(text: AgentRunner.cancelledSummary)))
        XCTAssertFalse(
            emitted.contains { event in
                if case .textChunk(let text) = event { return text.lowercased().contains("cancel") }
                return false
            },
            "the URLSession cancellation must never be reported as a failure"
        )
    }

    /// The stop has to leave the session coherent, not just stop producing:
    /// folding what a cancelled run emits must take the chat out of its
    /// running state and end the transcript with the stop.
    func test_cancelledRun_leavesTheSessionFinished() async {
        let started = expectation(description: "model call in flight")
        let events = UncheckedBox([BridgeEvent]())
        let runner = AgentRunner(
            client: HangingLLMClient(started: started),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event in events.value.append(event) }
        )

        let task = Task { await runner.run(command: "천천히 해줘") }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await task.value

        let session = ChatSession(id: "default", workspaceId: "default", title: "t", origin: .user)
        session.markWaitingForAgent()
        for event in events.value { session.apply(event) }

        XCTAssertFalse(session.isRunning)
        guard case .done(_, _, let summary)? = session.timeline.last else {
            return XCTFail("the transcript must end with a done row")
        }
        XCTAssertEqual(summary, AgentRunner.cancelledSummary)
    }

    /// A turn can ask for several tools. Stopping during the first one must
    /// not let the rest of the turn run -- checking cancellation only between
    /// model calls would still execute every remaining call in the batch.
    func test_run_cancelledDuringATool_doesNotRunTheRestOfTheTurn() async {
        let fake = FakeLLMClient()
        fake.turns = [
            GPTTurn(
                text: nil,
                toolCalls: [
                    GPTToolCall(id: "call-1", name: "run_shell", argumentsJSON: "{\"command\":\"ls\"}"),
                    GPTToolCall(id: "call-2", name: "run_shell", argumentsJSON: "{\"command\":\"pwd\"}"),
                ]
            ),
        ]
        let events = UncheckedBox([BridgeEvent]())
        let approvals = UncheckedBox([String]())
        let runTask = UncheckedBox(Task<Void, Never>?.none)

        let runner = AgentRunner(
            client: fake,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, approvalId in
                approvals.value.append(approvalId)
                // 중지 while the first tool's approval banner is up.
                runTask.value?.cancel()
                return false
            },
            emit: { event in events.value.append(event) }
        )

        // The gate exists so `runTask` is definitely set before the approval
        // gate reaches for it -- otherwise the cancel would be a no-op on some
        // runs and the test would only sometimes exercise the fix.
        let release = UncheckedBox(false)
        let task = Task {
            while !release.value { await Task.yield() }
            await runner.run(command: "두 개 해줘")
        }
        runTask.value = task
        release.value = true
        await task.value

        XCTAssertEqual(approvals.value, ["call-1"], "the second tool must never be asked about")
        XCTAssertEqual(events.value.last, .agentDone(ok: false, summary: AgentRunner.cancelledSummary))
        XCTAssertEqual(fake.sendCount, 1, "no further turn may be requested after a stop")
    }

    func test_pathArgument_extractsAPresentNonEmptyPath() {
        let arguments = JSONValue.object(["path": .string("src/main.swift")])

        XCTAssertEqual(AgentRunner.pathArgument(from: arguments), "src/main.swift")
    }

    func test_pathArgument_nilForMissingKey() {
        XCTAssertNil(AgentRunner.pathArgument(from: .object([:])))
    }

    func test_pathArgument_nilForEmptyString() {
        XCTAssertNil(AgentRunner.pathArgument(from: .object(["path": .string("")])))
    }

    func test_pathArgument_nilForWrongType() {
        XCTAssertNil(AgentRunner.pathArgument(from: .object(["path": .number(1)])))
    }

    func test_pathArgument_nilWhenArgumentsAreNotAnObject() {
        XCTAssertNil(AgentRunner.pathArgument(from: .string("not an object")))
    }
}

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

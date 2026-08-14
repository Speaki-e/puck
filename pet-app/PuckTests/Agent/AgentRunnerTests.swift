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

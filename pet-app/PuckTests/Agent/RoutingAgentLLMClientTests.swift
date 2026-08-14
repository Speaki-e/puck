//
//  RoutingAgentLLMClientTests.swift
//  Puck
//
//  F15 (task 8, gap 2 fix) test · owner: 박해영 (Haeyoung Park)
//  Proves a provider switch in Settings takes effect on the very next `send`
//  without reconstructing `AgentRunner`/`AgentHost` -- the property
//  `makeAgentLLMClient`'s doc comment promises now that provider selection
//  happens per request instead of once at `AgentHost.init`.
//

import XCTest
@testable import Puck

final class RoutingAgentLLMClientTests: XCTestCase {

    func test_send_routesToOpenAI_thenToAnthropic_afterProviderChanges_withoutRebuildingClient() async throws {
        let openAI = SpyAgentLLMClient(name: "openai")
        let anthropic = SpyAgentLLMClient(name: "anthropic")
        var provider = AgentProvider.openai

        let router = RoutingAgentLLMClient(
            configuration: {
                AgentConfiguration(apiKey: "key", model: "m", provider: provider, keySource: nil)
            },
            openAIClient: openAI,
            anthropicClient: anthropic
        )

        _ = try await router.send(messages: [.user("first")], tools: [])
        XCTAssertEqual(openAI.receivedMessageCounts, [1])
        XCTAssertEqual(anthropic.receivedMessageCounts, [])

        // Flip the provider the same way Settings does -- through the
        // closure's next read, not a new AgentConfiguration captured once.
        provider = .anthropic
        _ = try await router.send(messages: [.user("second")], tools: [])

        XCTAssertEqual(openAI.receivedMessageCounts, [1], "the OpenAI client must not see the post-switch turn")
        XCTAssertEqual(anthropic.receivedMessageCounts, [1], "the switch must take effect on the very next send")
    }
}

private final class SpyAgentLLMClient: AgentLLMClient {
    let name: String
    private(set) var receivedMessageCounts: [Int] = []

    init(name: String) {
        self.name = name
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        receivedMessageCounts.append(messages.count)
        return GPTTurn(text: name, toolCalls: [])
    }
}

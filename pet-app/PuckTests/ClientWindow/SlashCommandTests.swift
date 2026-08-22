//
//  SlashCommandTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class SlashCommandTests: XCTestCase {
    func test_parsesEveryCommand() {
        XCTAssertEqual(SlashCommand.parse("/help"), .help)
        XCTAssertEqual(SlashCommand.parse("/fast"), .fast)
        XCTAssertEqual(SlashCommand.parse("/model"), .model(nil))
        XCTAssertEqual(SlashCommand.parse("/model gpt-5.5"), .model("gpt-5.5"))
        XCTAssertEqual(SlashCommand.parse("/effort"), .effort(nil))
        XCTAssertEqual(SlashCommand.parse("/effort high"), .effort(.high))
    }

    /// Ordinary prose has to go to the agent untouched, or a message that
    /// happens to mention a path never gets sent.
    func test_leavesThingsThatAreNotCommandsAlone() {
        XCTAssertNil(SlashCommand.parse("안녕하세요"))
        XCTAssertNil(SlashCommand.parse("/usr/bin/env 를 봐줘"), "a path is not a command")
        XCTAssertNil(SlashCommand.parse("/"), "a lone slash is not a command")
        XCTAssertNil(SlashCommand.parse("/1234"))
        XCTAssertNil(SlashCommand.parse("경로는 /help 처럼 쓰세요"), "a command has to start the message")
    }

    /// A typo'd command must not become a question to the agent, which would
    /// answer it as prose.
    func test_reportsAnUnknownCommandRatherThanSendingIt() {
        XCTAssertEqual(SlashCommand.parse("/mdoel"), .unknown("/mdoel"))
        XCTAssertEqual(SlashCommand.parse("/effort yolo"), .unknown("/effort yolo"))
    }

    func test_leadingAndTrailingSpaceDoesNotHideACommand() {
        XCTAssertEqual(SlashCommand.parse("  /fast  "), .fast)
        XCTAssertEqual(SlashCommand.parse("/model   gpt-5.5  "), .model("gpt-5.5"))
    }

    func test_helpNamesEveryCommandItCanRun() {
        let help = SlashCommandRunner().run(.help)
        for name in SlashCommand.names {
            XCTAssertTrue(help.contains("/\(name)"), "/help does not mention /\(name)")
        }
    }
}

final class SlashCommandRunnerTests: XCTestCase {
    /// Records what a command wrote, so a test never touches the real `.env`.
    private final class Writes {
        private(set) var pairs: [(String, String?)] = []
        var succeeds = true
        func write(_ key: String, _ value: String?) -> Bool {
            pairs.append((key, value))
            return succeeds
        }
    }

    private func runner(
        _ writes: Writes,
        provider: AgentProvider = .openai,
        effort: AgentEffort = .medium
    ) -> SlashCommandRunner {
        SlashCommandRunner(
            configuration: { AgentConfiguration.load(environment: ["AGENT_PROVIDER": provider.rawValue], searchPaths: []) },
            currentEffort: { effort },
            write: writes.write
        )
    }

    func test_fastWritesTheLowestEffort() {
        let writes = Writes()
        _ = runner(writes, effort: .low).run(.fast)
        XCTAssertEqual(writes.pairs.map(\.0), [AgentEffort.environmentVariable])
        XCTAssertEqual(writes.pairs.first?.1, "low")
    }

    func test_effortWithNoArgumentWritesNothing() {
        let writes = Writes()
        let reply = runner(writes, effort: .high).run(.effort(nil))
        XCTAssertTrue(writes.pairs.isEmpty, "showing a setting must not change it")
        XCTAssertTrue(reply.contains(AgentEffort.high.displayName))
    }

    /// The CLI runs on its own configuration, so offering to set a model
    /// there would be a promise the provider cannot keep.
    func test_modelSaysTheCLIHasNoneToChoose() {
        let writes = Writes()
        let reply = runner(writes, provider: .cli).run(.model("gpt-5.5"))
        XCTAssertTrue(writes.pairs.isEmpty)
        XCTAssertTrue(reply.contains(AgentProvider.cli.displayName))
    }

    func test_modelWritesForAProviderThatHasOne() {
        let writes = Writes()
        _ = runner(writes, provider: .openai).run(.model("gpt-5.5"))
        XCTAssertEqual(writes.pairs.map(\.0), ["AGENT_MODEL"])
        XCTAssertEqual(writes.pairs.first?.1, "gpt-5.5")
    }

    /// A write that failed must say so rather than report the new value.
    func test_aFailedWriteIsReported() {
        let writes = Writes()
        writes.succeeds = false
        XCTAssertEqual(runner(writes).run(.fast), Strings.text(.slashWriteFailed))
    }
}

final class AgentEffortTests: XCTestCase {
    func test_unsetAndUnrecognizedResolveToTheDefault() {
        XCTAssertEqual(AgentEffort.resolved(fromRawValue: nil), .medium)
        XCTAssertEqual(AgentEffort.resolved(fromRawValue: "turbo"), .medium)
    }

    /// The default adds no instruction: telling an agent to think normally is
    /// noise, and its own tuning is what "normal" means.
    func test_onlyTheEndsCarryAnInstruction() {
        XCTAssertNil(AgentEffort.medium.promptLine)
        XCTAssertNotNil(AgentEffort.low.promptLine)
        XCTAssertNotNil(AgentEffort.high.promptLine)
    }

    func test_readsFromTheEnvironment() {
        XCTAssertEqual(AgentConfiguration.effort(environment: ["AGENT_EFFORT": "high"], searchPaths: []), .high)
        XCTAssertEqual(AgentConfiguration.effort(environment: [:], searchPaths: []), .medium)
    }
}

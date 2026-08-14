//
//  AgentConfigurationTests.swift
//  Puck
//
//  F15 test · owner: 박해영 (Haeyoung Park)
//  Reading the key out of a .env, and the precedence between the places one
//  can live -- getting this wrong looks like "the key I just set is being
//  ignored", which is a miserable thing to debug.
//

import XCTest
@testable import Puck

final class DotEnvTests: XCTestCase {
    func test_readsPlainAssignments() {
        let parsed = DotEnv.parse("OPENAI_API_KEY=sk-abc\nOPENAI_MODEL=gpt-4o")

        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk-abc")
        XCTAssertEqual(parsed["OPENAI_MODEL"], "gpt-4o")
    }

    func test_ignoresCommentsAndBlankLines() {
        let parsed = DotEnv.parse("""
        # the agent's key

        OPENAI_API_KEY=sk-abc
        """)

        XCTAssertEqual(parsed, ["OPENAI_API_KEY": "sk-abc"])
    }

    func test_acceptsExportPrefixAndQuotes() {
        let parsed = DotEnv.parse("""
        export OPENAI_API_KEY="sk-abc"
        OPENAI_MODEL='gpt-4o'
        """)

        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk-abc")
        XCTAssertEqual(parsed["OPENAI_MODEL"], "gpt-4o")
    }

    /// Keys contain '='. Splitting on every one of them silently truncates the
    /// key, which then fails as a 401 rather than as a parse error.
    func test_splitsOnTheFirstEqualsOnly() {
        let parsed = DotEnv.parse("OPENAI_API_KEY=sk-abc==tail")

        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk-abc==tail")
    }

    func test_missingFileIsEmptyRatherThanAFailure() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/.env")

        XCTAssertTrue(DotEnv.parse(fileAt: missing).isEmpty)
    }
}

final class AgentConfigurationTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        directories = []
        super.tearDown()
    }

    /// A temp directory holding a .env with `contents`.
    private func directory(withEnv contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        try contents.write(to: url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        return url
    }

    func test_readsTheKeyAndModelFromADotEnv() throws {
        let directory = try directory(withEnv: "OPENAI_API_KEY=sk-from-file\nOPENAI_MODEL=gpt-4.1")

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [directory])

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertEqual(configuration.apiKey, "sk-from-file")
        XCTAssertEqual(configuration.model, "gpt-4.1")
    }

    func test_environmentBeatsTheFile_soAOneOffOverrideNeedsNoEdit() throws {
        let directory = try directory(withEnv: "OPENAI_API_KEY=sk-from-file")

        let configuration = AgentConfiguration.load(
            environment: ["OPENAI_API_KEY": "sk-from-environment"],
            searchPaths: [directory]
        )

        XCTAssertEqual(configuration.apiKey, "sk-from-environment")
    }

    /// Nearest-first: the first .env that supplies a value owns it, so adding
    /// a fallback file can never shadow the one next to the project.
    func test_theEarlierSearchPathWins() throws {
        let nearer = try directory(withEnv: "OPENAI_API_KEY=sk-nearer")
        let further = try directory(withEnv: "OPENAI_API_KEY=sk-further\nOPENAI_MODEL=gpt-4.1")

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [nearer, further])

        XCTAssertEqual(configuration.apiKey, "sk-nearer")
        // …but a value only the further file has still comes through.
        XCTAssertEqual(configuration.model, "gpt-4.1")
    }

    /// The `#filePath` walk has to land on the repo root, or `pet-app/.env`
    /// -- the whole point of that search path -- is looked for in the wrong
    /// directory and silently never found.
    func test_repositoryDirectoryIsTheRepoRoot() throws {
        let repository = try XCTUnwrap(AgentConfiguration.repositoryDirectory, "Debug builds must resolve a repo directory")

        XCTAssertEqual(repository.lastPathComponent, "pet-app")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: repository.appendingPathComponent("project.yml").path),
            "expected the repo root to contain project.yml, got \(repository.path)"
        )
        XCTAssertTrue(
            AgentConfiguration.defaultSearchPaths.contains(repository),
            ".env next to project.yml has to actually be searched"
        )
    }

    func test_noKeyAnywhere_isNotConfiguredAndStillHasADefaultModel() {
        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.model, AgentConfiguration.defaultModel)
    }

    /// An empty assignment is the same as not setting it -- otherwise an
    /// `OPENAI_API_KEY=` left in a file reports "configured" and fails at the
    /// API instead of at startup.
    func test_blankValuesCountAsAbsent() throws {
        let directory = try directory(withEnv: "OPENAI_API_KEY=\nOPENAI_MODEL=   ")

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [directory])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.model, AgentConfiguration.defaultModel)
    }

    // MARK: - Provider

    func test_defaultsToOpenAIWhenNothingSelectsAProvider() {
        let config = AgentConfiguration.load(environment: [:], searchPaths: [])
        XCTAssertEqual(config.provider, .openai)
    }

    func test_readsProviderFromEnvironment() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "anthropic"], searchPaths: [])
        XCTAssertEqual(config.provider, .anthropic)
    }

    func test_unknownProviderFallsBackToOpenAI() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "gemini"], searchPaths: [])
        XCTAssertEqual(config.provider, .openai)
    }

    func test_selectedProviderDecidesWhichKeyIsRead() {
        let env = ["AGENT_PROVIDER": "anthropic", "ANTHROPIC_API_KEY": "sk-ant-x", "OPENAI_API_KEY": "sk-oai-y"]
        XCTAssertEqual(AgentConfiguration.load(environment: env, searchPaths: []).apiKey, "sk-ant-x")

        var openAIEnv = env
        openAIEnv["AGENT_PROVIDER"] = "openai"
        XCTAssertEqual(AgentConfiguration.load(environment: openAIEnv, searchPaths: []).apiKey, "sk-oai-y")
    }

    func test_eachProviderHasItsOwnDefaultModel() {
        let openAI = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "openai"], searchPaths: [])
        let anthropic = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "anthropic"], searchPaths: [])
        XCTAssertNotEqual(openAI.model, anthropic.model)
        XCTAssertFalse(anthropic.model.isEmpty)
    }

    /// `AGENT_MODEL` is a provider-neutral override, but a legacy
    /// `OPENAI_MODEL` must keep winning for OpenAI users -- adding the
    /// neutral variable can't silently change behavior for anyone who
    /// already relies on the specific one.
    func test_legacyOpenAIModelVariableStillWinsOverProviderNeutralOne() {
        let config = AgentConfiguration.load(
            environment: ["OPENAI_MODEL": "gpt-4.1", "AGENT_MODEL": "gpt-5"],
            searchPaths: []
        )

        XCTAssertEqual(config.model, "gpt-4.1")
    }

    /// With no provider-specific override, the neutral variable still works
    /// -- it exists precisely so a provider switch doesn't also require
    /// renaming the model override.
    func test_agentModelIsUsedWhenNoProviderSpecificOverrideIsSet() {
        let config = AgentConfiguration.load(
            environment: ["AGENT_PROVIDER": "anthropic", "AGENT_MODEL": "claude-opus-5"],
            searchPaths: []
        )

        XCTAssertEqual(config.model, "claude-opus-5")
    }
}

/// F15 (task 4): `makeAgentLLMClient` is the single place `AgentHost`'s
/// construction site (PuckClient/AgentHost.swift) picks a client class --
/// getting this switch wrong means every request goes to the wrong host
/// regardless of which key Settings has stored.
final class MakeAgentLLMClientTests: XCTestCase {
    func test_factoryReturnsTheClientMatchingTheSelectedProvider() {
        let openAI = makeAgentLLMClient({ AgentConfiguration.load(environment: ["AGENT_PROVIDER": "openai"], searchPaths: []) })
        XCTAssertTrue(openAI is GPTClient)

        let anthropic = makeAgentLLMClient({ AgentConfiguration.load(environment: ["AGENT_PROVIDER": "anthropic"], searchPaths: []) })
        XCTAssertTrue(anthropic is ClaudeClient)
    }

    /// No `AGENT_PROVIDER` at all resolves to `.openai` (AgentConfiguration's
    /// own default) -- the factory has to follow that fallback rather than
    /// crash or pick arbitrarily.
    func test_factoryDefaultsToGPTClientWhenNoProviderIsSet() {
        let client = makeAgentLLMClient({ AgentConfiguration.load(environment: [:], searchPaths: []) })
        XCTAssertTrue(client is GPTClient)
    }
}

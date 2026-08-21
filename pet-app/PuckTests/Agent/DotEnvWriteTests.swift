//
//  DotEnvWriteTests.swift
//  Puck
//
//  F15 test · owner: 박해영 (Haeyoung Park)
//  Saving a key from the settings panel. The two things that would be quietly
//  destructive if wrong: eating the rest of the file, and leaving an API key
//  world-readable.
//

import XCTest
@testable import Puck

final class DotEnvWriteTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var envFile: URL { directory.appendingPathComponent(".env") }

    private func contents() throws -> String {
        try String(contentsOf: envFile, encoding: .utf8)
    }

    func test_writesAKeyIntoAFileThatDidNotExist() throws {
        XCTAssertTrue(DotEnv.write(key: "OPENAI_API_KEY", value: "sk-new", to: envFile))

        XCTAssertEqual(DotEnv.parse(fileAt: envFile)["OPENAI_API_KEY"], "sk-new")
    }

    /// The shipped .env is a commented template; saving a key must not wipe
    /// the instructions that tell the next person what the file is for.
    func test_preservesCommentsAndOtherKeys() throws {
        try """
        # Puck agent config
        OPENAI_MODEL=gpt-4o
        """.write(to: envFile, atomically: true, encoding: .utf8)

        DotEnv.write(key: "OPENAI_API_KEY", value: "sk-new", to: envFile)

        let written = try contents()
        XCTAssertTrue(written.contains("# Puck agent config"))
        XCTAssertEqual(DotEnv.parse(written)["OPENAI_MODEL"], "gpt-4o")
        XCTAssertEqual(DotEnv.parse(written)["OPENAI_API_KEY"], "sk-new")
    }

    func test_replacesAnExistingAssignmentInPlaceRatherThanAppendingASecond() throws {
        try "OPENAI_API_KEY=sk-old\nOPENAI_MODEL=gpt-4o".write(to: envFile, atomically: true, encoding: .utf8)

        DotEnv.write(key: "OPENAI_API_KEY", value: "sk-new", to: envFile)

        let written = try contents()
        XCTAssertEqual(DotEnv.parse(written)["OPENAI_API_KEY"], "sk-new")
        XCTAssertEqual(written.components(separatedBy: "OPENAI_API_KEY=").count - 1, 1, "the old line must be replaced, not shadowed")
    }

    /// Remove falls back to whatever other source was being shadowed, so the
    /// line has to actually go rather than becoming an empty assignment.
    func test_nilValueRemovesTheAssignment() throws {
        try "OPENAI_API_KEY=sk-old\nOPENAI_MODEL=gpt-4o".write(to: envFile, atomically: true, encoding: .utf8)

        DotEnv.write(key: "OPENAI_API_KEY", value: nil, to: envFile)

        let written = try contents()
        XCTAssertNil(DotEnv.parse(written)["OPENAI_API_KEY"])
        XCTAssertEqual(DotEnv.parse(written)["OPENAI_MODEL"], "gpt-4o")
    }

    /// It holds an API key. The default 0644 would make it readable by every
    /// process on the machine.
    func test_theKeyFileIsOnlyReadableByItsOwner() throws {
        DotEnv.write(key: "OPENAI_API_KEY", value: "sk-new", to: envFile)

        let permissions = try FileManager.default.attributesOfItem(atPath: envFile.path)[.posixPermissions] as? NSNumber

        XCTAssertEqual(permissions?.int16Value, 0o600)
    }

    /// Saving twice is the normal case (paste, then correct a typo) -- the
    /// atomic write replaces the file, so permissions have to be re-applied.
    func test_permissionsSurviveASecondWrite() throws {
        DotEnv.write(key: "OPENAI_API_KEY", value: "sk-one", to: envFile)
        DotEnv.write(key: "OPENAI_API_KEY", value: "sk-two", to: envFile)

        let permissions = try FileManager.default.attributesOfItem(atPath: envFile.path)[.posixPermissions] as? NSNumber

        XCTAssertEqual(permissions?.int16Value, 0o600)
    }
}

final class AgentConfigurationKeySourceTests: XCTestCase {
    func test_reportsTheEnvironmentWhenItSuppliedTheKey() {
        let configuration = AgentConfiguration.load(
            environment: ["AGENT_PROVIDER": "openai", "OPENAI_API_KEY": "sk-env"],
            searchPaths: []
        )

        XCTAssertEqual(configuration.keySource, .environment(variable: "OPENAI_API_KEY"))
    }

    func test_reportsTheFileThatSuppliedTheKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(".env")
        try "AGENT_PROVIDER=openai\nOPENAI_API_KEY=sk-file".write(to: file, atomically: true, encoding: .utf8)

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [directory])

        XCTAssertEqual(configuration.keySource, .file(file))
    }

    func test_noKeyHasNoSource() {
        XCTAssertNil(AgentConfiguration.load(environment: [:], searchPaths: []).keySource)
    }
}

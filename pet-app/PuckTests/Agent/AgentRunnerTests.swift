//
//  AgentRunnerTests.swift
//  Puck
//
//  Covers AgentRunner.pathArgument only -- the pure, self-contained piece
//  of the read_file/open_in_editor wiring. The turn loop itself (perform(_:),
//  toolSpecs assembly) has no test coverage anywhere in this codebase yet,
//  since exercising it needs GPTClient/network mocking that doesn't exist
//  either; closing that gap is a separate, larger undertaking than adding
//  these two tools.
//

import XCTest
@testable import Puck

final class AgentRunnerTests: XCTestCase {
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

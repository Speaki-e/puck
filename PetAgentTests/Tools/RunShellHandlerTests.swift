//
//  RunShellHandlerTests.swift
//  PetAgent
//
//  F11 test · owner: Haeyoung Park
//  Argument validation + a real (harmless) command execution.
//

import XCTest
@testable import PetAgent

final class RunShellHandlerTests: XCTestCase {
    func test_missingCommand_failsWithExecutionFailed() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("run_shell requires a command string"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_validCommand_returnsStdoutAndExitCode() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object(["command": .string("echo hello")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data else {
                    XCTFail("expected object result")
                    return
                }
                XCTAssertEqual(fields["stdout"], .string("hello\n"))
                XCTAssertEqual(fields["exit_code"], .number(0))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }
}

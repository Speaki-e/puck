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

    /// A child process writing more than the OS pipe buffer (64KB on macOS)
    /// blocks in write() until the parent drains the pipe. Waiting for exit
    /// before reading therefore deadlocks: the parent waits for a process that
    /// is waiting for the parent. Any real command the agent runs (a build, a
    /// test run, `git log`) clears 64KB easily.
    func test_outputLargerThanPipeBuffer_completesWithFullOutput() {
        let handler = RunShellHandler()
        let byteCount = 200_000

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object(["command": .string("printf 'x%.0s' {1..\(byteCount)}")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data else {
                    XCTFail("expected object result")
                    return
                }
                guard case .string(let stdout)? = fields["stdout"] else {
                    XCTFail("expected stdout string")
                    return
                }
                XCTAssertEqual(stdout.count, byteCount, "stdout was truncated at the pipe buffer boundary")
                XCTAssertEqual(fields["exit_code"], .number(0))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    /// stderr fills its own pipe independently — draining only stdout still
    /// deadlocks a command that is noisy on stderr.
    func test_stderrLargerThanPipeBuffer_completesWithFullOutput() {
        let handler = RunShellHandler()
        let byteCount = 200_000

        let expectation = expectation(description: "completion called")
        handler.execute(args: .object(["command": .string("printf 'e%.0s' {1..\(byteCount)} 1>&2")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data, case .string(let stderr)? = fields["stderr"] else {
                    XCTFail("expected stderr string")
                    return
                }
                XCTAssertEqual(stderr.count, byteCount, "stderr was truncated at the pipe buffer boundary")
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }
}

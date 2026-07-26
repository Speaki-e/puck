//
//  ToolExecutorTests.swift
//  PetAgent
//
//  F11 test · owner: 박해영 (Haeyoung Park)
//  tool_dispatch routing + per-call timeout, per protocol/01_protocol.md 3.1/4.
//

import XCTest
@testable import PetAgent

private final class StubHandler: ToolHandler {
    let toolName: String
    private let behavior: (JSONValue, @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) -> Void

    init(toolName: String, behavior: @escaping (JSONValue, @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) -> Void) {
        self.toolName = toolName
        self.behavior = behavior
    }

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        behavior(args, completion)
    }
}

final class ToolExecutorTests: XCTestCase {
    func test_dispatchesToRegisteredHandler_andReturnsItsData() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "launch_app") { _, completion in
            completion(.success(.object(["pid": .number(501)])))
        })

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t1", tool: "launch_app", args: .object([:]))) { result in
            XCTAssertEqual(result.id, "t1")
            XCTAssertTrue(result.ok)
            XCTAssertEqual(result.data, .object(["pid": .number(501)]))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_handlerFailure_producesErrorResult() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "run_shell") { _, completion in
            completion(.failure(.executionFailed("boom")))
        })

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t2", tool: "run_shell", args: .object([:]))) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, "execution_failed")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_unregisteredTool_producesExecutionFailedError() {
        let executor = ToolExecutor()

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t3", tool: "does_not_exist", args: .object([:]))) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, "execution_failed")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_handlerExceedingTimeout_producesTimeoutError() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "slow") { _, _ in
            // never calls completion
        })

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t4", tool: "slow", args: .object([:])), timeout: 0.05) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, "timeout")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_lateCompletionAfterTimeout_isIgnored() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "slow") { _, completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                completion(.success(nil)) // arrives after the timeout already fired
            }
        })

        var callCount = 0
        let firstCompletion = expectation(description: "timeout completion")
        let unexpectedSecondCompletion = XCTestExpectation(description: "late completion should be ignored")
        unexpectedSecondCompletion.isInverted = true

        executor.dispatch(ToolDispatch(id: "t5", tool: "slow", args: .object([:])), timeout: 0.05) { result in
            callCount += 1
            if callCount == 1 {
                XCTAssertEqual(result.error, "timeout")
                firstCompletion.fulfill()
            } else {
                unexpectedSecondCompletion.fulfill()
            }
        }

        wait(for: [firstCompletion, unexpectedSecondCompletion], timeout: 0.5)
        XCTAssertEqual(callCount, 1)
    }
}

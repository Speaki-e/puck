//
//  BridgeMessageRouterTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  BridgeServer delivers messages on its own background queue, but handling
//  them touches main-thread-only state: EventRouter reactions drive
//  CharacterController -> USDZAvatar (RealityKit entity mutation), and
//  pet-app-executor handlers read NSWorkspace / WindowListWatcher.windows,
//  which the 10Hz poll timer owns on main. These tests pin the hop to main.
//

import XCTest
@testable import PetAgent

private final class ThreadRecordingHandler: ToolHandler {
    let toolName = "launch_app"
    private(set) var ranOnMainThread: Bool?

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        ranOnMainThread = Thread.isMainThread
        completion(.success(.object(["pid": .number(1)])))
    }
}

final class BridgeMessageRouterTests: XCTestCase {
    private let backgroundQueue = DispatchQueue(label: "test.bridge.delivery")

    func test_eventReaction_isDeliveredOnMainThread_whenMessageArrivesOffMain() {
        let router = BridgeMessageRouter(toolExecutor: ToolExecutor())

        var reactedOnMainThread: Bool?
        let reacted = expectation(description: "event reaction delivered")
        router.onEventReaction = { _ in
            reactedOnMainThread = Thread.isMainThread
            reacted.fulfill()
        }

        backgroundQueue.async {
            router.handle(.event(.agentThinking), reply: { _ in })
        }

        wait(for: [reacted], timeout: 2)
        XCTAssertEqual(reactedOnMainThread, true)
    }

    func test_toolHandler_runsOnMainThread_whenDispatchArrivesOffMain() {
        let handler = ThreadRecordingHandler()
        let executor = ToolExecutor()
        executor.register(handler)
        let router = BridgeMessageRouter(toolExecutor: executor)

        let replied = expectation(description: "tool_result replied")
        backgroundQueue.async {
            router.handle(
                .toolDispatch(ToolDispatch(id: "t1", tool: "launch_app", args: .object([:]))),
                reply: { message in
                    guard case .toolResult(let result) = message else {
                        XCTFail("expected tool_result, got \(message)")
                        return
                    }
                    XCTAssertEqual(result.id, "t1")
                    XCTAssertTrue(result.ok)
                    replied.fulfill()
                }
            )
        }

        wait(for: [replied], timeout: 2)
        XCTAssertEqual(handler.ranOnMainThread, true)
    }

    func test_reaction_matchesEventRouter() {
        let router = BridgeMessageRouter(toolExecutor: ToolExecutor())

        var received: EventReaction?
        let reacted = expectation(description: "event reaction delivered")
        router.onEventReaction = { reaction in
            received = reaction
            reacted.fulfill()
        }

        router.handle(.event(.agentDone(ok: true, summary: "done")), reply: { _ in })

        wait(for: [reacted], timeout: 2)
        XCTAssertEqual(received, EventRouter.reaction(for: .agentDone(ok: true, summary: "done")))
    }

    /// protocol 3.1: a tool_cancel from workspace reaches the executor and the
    /// original dispatch's reply comes back as error="cancelled".
    func test_toolCancel_cancelsTheInFlightDispatch() {
        final class NeverCompletingHandler: ToolHandler {
            let toolName = "slow"
            func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {}
        }
        let executor = ToolExecutor()
        executor.register(NeverCompletingHandler())
        let router = BridgeMessageRouter(toolExecutor: executor)

        let replied = expectation(description: "cancelled tool_result replied")
        router.handle(
            .toolDispatch(ToolDispatch(id: "t7", tool: "slow", args: .object([:]))),
            reply: { message in
                guard case .toolResult(let result) = message else {
                    XCTFail("expected tool_result, got \(message)")
                    return
                }
                XCTAssertEqual(result.id, "t7")
                XCTAssertFalse(result.ok)
                XCTAssertEqual(result.error, "cancelled")
                replied.fulfill()
            }
        )
        router.handle(.toolCancel(id: "t7"), reply: { _ in XCTFail("tool_cancel itself gets no reply") })

        wait(for: [replied], timeout: 2)
    }

    func test_messagesPetAppOnlySends_areIgnored() {
        let router = BridgeMessageRouter(toolExecutor: ToolExecutor())
        router.onEventReaction = { _ in XCTFail("should not react to a message pet-app only sends") }

        router.handle(.userInput(UserInput(text: "hi", source: .text)), reply: { _ in XCTFail("should not reply") })
        router.handle(.toolResult(ToolResult(id: "t1", ok: true, data: nil, error: nil)), reply: { _ in XCTFail("should not reply") })

        // Give any (incorrect) async hop a chance to run before the test ends.
        let settled = expectation(description: "settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }
}

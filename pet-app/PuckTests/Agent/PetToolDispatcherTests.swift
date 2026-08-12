//
//  PetToolDispatcherTests.swift
//  Puck
//
//  F15 test · owner: 박해영 (Haeyoung Park)
//  Correlating a tool_result back to the call that is waiting for it -- the
//  dispatcher's whole job, and the part that silently strands a run if it is
//  wrong.
//

import XCTest
@testable import Puck

final class PetToolDispatcherTests: XCTestCase {
    /// Records what was put on the socket, and lets a test answer it.
    private final class Wire {
        private(set) var sent: [BridgeMessage] = []
        var isConnected = true

        func send(_ message: BridgeMessage) -> Bool {
            guard isConnected else { return false }
            sent.append(message)
            return true
        }

        var lastDispatch: ToolDispatch? {
            guard case .toolDispatch(let dispatch) = sent.last else { return nil }
            return dispatch
        }
    }

    func test_resultWithMatchingId_resolvesTheCall() async {
        let wire = Wire()
        let sut = PetToolDispatcher(send: wire.send)

        async let result = sut.execute(tool: "launch_app", arguments: .object(["app_name": .string("Weather")]), id: "t1")
        await waitForDispatch(on: wire)
        sut.handle(ToolResult(id: "t1", ok: true, data: .object(["pid": .number(501)]), error: nil))

        let awaited = await result
        XCTAssertTrue(awaited.ok)
        XCTAssertEqual(wire.lastDispatch?.tool, "launch_app")
    }

    /// A reply for someone else's id must not resolve this call -- otherwise
    /// two concurrent tools hand each other's answers to the model.
    func test_resultWithAnotherId_leavesTheCallWaiting() async {
        let wire = Wire()
        let sut = PetToolDispatcher(send: wire.send)

        async let result = sut.execute(tool: "launch_app", arguments: .object([:]), id: "mine")
        await waitForDispatch(on: wire)
        sut.handle(ToolResult(id: "someone-else", ok: true, data: nil, error: nil))
        sut.handle(ToolResult(id: "mine", ok: false, data: nil, error: .executionFailed))

        let awaited = await result
        XCTAssertEqual(awaited.error, "execution_failed")
    }

    func test_nothingConnected_failsImmediatelyRatherThanWaitingOutTheTimeout() async {
        let wire = Wire()
        wire.isConnected = false
        let sut = PetToolDispatcher(send: wire.send)

        let result = await sut.execute(tool: "launch_app", arguments: .object([:]), id: "t1")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "pet_app_disconnected")
    }

    func test_toolOutsideTheRegistry_isRejectedBeforeItReachesTheSocket() async {
        let wire = Wire()
        let sut = PetToolDispatcher(send: wire.send)

        let result = await sut.execute(tool: "make_coffee", arguments: .object([:]), id: "t1")

        XCTAssertEqual(result.error, "unknown_tool")
        XCTAssertTrue(wire.sent.isEmpty, "an unregistered tool must not be dispatched")
    }

    func test_socketDrop_failsEverythingInFlight() async {
        let wire = Wire()
        let sut = PetToolDispatcher(send: wire.send)

        async let result = sut.execute(tool: "run_shell", arguments: .object([:]), id: "t1")
        await waitForDispatch(on: wire)
        sut.failAllInFlight()

        let awaited = await result
        XCTAssertEqual(awaited.error, "pet_app_disconnected")
    }

    /// execute() suspends inside withCheckedContinuation, so the dispatch is
    /// on the wire a moment after the async let starts. Polling beats a fixed
    /// sleep, which is either flaky or slow.
    private func waitForDispatch(on wire: Wire) async {
        for _ in 0..<200 where wire.sent.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

final class AgentJSONBridgingTests: XCTestCase {
    func test_decodesToolArgumentsIntoTheObjectTheSocketWants() {
        let decoded = JSONValue.decodeObject(from: #"{"app_name":"Weather"}"#)

        XCTAssertEqual(decoded, .object(["app_name": .string("Weather")]))
    }

    /// Models emit "" or a bare fragment for no-argument tools often enough
    /// that failing the call over it would be the common case, not the edge.
    func test_unparseableArguments_becomeAnEmptyObjectRatherThanFailingTheCall() {
        XCTAssertEqual(JSONValue.decodeObject(from: ""), .object([:]))
        XCTAssertEqual(JSONValue.decodeObject(from: "not json"), .object([:]))
        XCTAssertEqual(JSONValue.decodeObject(from: "[1,2]"), .object([:]), "an array is not an argument object")
    }
}

final class AgentToolRegistryTests: XCTestCase {
    /// The three tools the plan gates behind approval, and nothing else.
    func test_approvalRequiredMatchesTheContract() {
        let gated = Set(ToolRegistry.all.filter(\.requiresApproval).map(\.name))

        XCTAssertEqual(gated, ["click_element", "run_shell", "run_applescript"])
    }

    /// Only pet-app's tools are offered to the model, because only pet-app
    /// has an executor -- see AgentRunner.toolSpecs.
    func test_petAppExecutorCoversEveryToolTheExecutorImplements() {
        let petAppTools = Set(ToolRegistry.tools(for: .petApp).map(\.name))

        XCTAssertEqual(petAppTools, [
            "launch_app", "list_running_apps", "get_frontmost_window", "find_ui_element",
            "point_at", "click_element", "run_shell", "run_applescript",
        ])
    }

    /// The registry mirror and the timeout mirror are separate files copied
    /// from protocol; a tool present in one and absent from the other is the
    /// drift both are meant to prevent.
    func test_everyRegistryToolHasItsRegistryTimeout() {
        for tool in ToolRegistry.all {
            XCTAssertEqual(
                tool.timeoutSeconds,
                ToolTimeouts.bySeconds[tool.name],
                "\(tool.name) is missing from ToolTimeouts"
            )
        }
    }

    /// And the other direction, which is the one that actually bit: the
    /// registry mirror shipped without `open_task_session` because it was
    /// added upstream while this file was being written, and checking only
    /// registry -> timeouts cannot see a tool the registry never listed.
    func test_everyTimeoutEntryHasARegistryTool() {
        for name in ToolTimeouts.bySeconds.keys {
            XCTAssertNotNil(ToolRegistry.tool(named: name), "\(name) is in ToolTimeouts but missing from ToolRegistry")
        }
    }
}

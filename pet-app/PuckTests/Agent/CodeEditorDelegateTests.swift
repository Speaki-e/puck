//
//  CodeEditorDelegateTests.swift
//  Puck
//
//  F15 test · owner: 박해영 (Haeyoung Park)
//  Delegating a coding task to workspace's agent and pairing its agent_done
//  back to the tool call that is waiting -- the same "strands the run if it's
//  wrong" territory as PetToolDispatcherTests, minus the id: correlation is
//  by session_id alone until protocol grows a request_id.
//

import XCTest
@testable import Puck

final class CodeEditorDelegateTests: XCTestCase {
    private final class Wire {
        private(set) var sent: [(task: String, workspaceId: String, sessionId: String)] = []
        var isConnected = true

        func send(_ task: String, _ workspaceId: String, _ sessionId: String) -> Bool {
            guard isConnected else { return false }
            sent.append((task, workspaceId, sessionId))
            return true
        }
    }

    func test_agentDoneForTheSession_resolvesTheCallWithItsSummary() async {
        let wire = Wire()
        let sut = CodeEditorDelegate(send: wire.send)

        async let result = sut.execute(task: "hello.ts에 주석 달아줘", workspaceId: "default", sessionId: "s1")
        await waitForSend(on: wire)
        sut.handle(.agentDone(ok: true, summary: "hello.ts에 주석을 추가했습니다"), sessionId: "s1")

        let awaited = await result
        XCTAssertTrue(awaited.ok)
        XCTAssertEqual(awaited.data, .string("hello.ts에 주석을 추가했습니다"))
        // The task goes out as user_input text, unchanged and addressed to the
        // session it came from.
        XCTAssertEqual(wire.sent.first?.task, "hello.ts에 주석 달아줘")
        XCTAssertEqual(wire.sent.first?.sessionId, "s1")
    }

    /// Another session finishing its own run must not answer this call --
    /// session_id is the only thing pairing them.
    func test_agentDoneForAnotherSession_leavesTheCallWaiting() async {
        let wire = Wire()
        let sut = CodeEditorDelegate(send: wire.send)

        async let result = sut.execute(task: "고쳐줘", workspaceId: "default", sessionId: "mine")
        await waitForSend(on: wire)
        sut.handle(.agentDone(ok: true, summary: "다른 세션"), sessionId: "someone-else")
        sut.handle(.agentDone(ok: false, summary: "내 세션 실패"), sessionId: "mine")

        let awaited = await result
        XCTAssertFalse(awaited.ok)
        XCTAssertEqual(awaited.detail, "내 세션 실패")
    }

    /// Everything else workspace emits during the edit is transcript material,
    /// not an answer -- resolving on one would return before the edit is done.
    func test_otherEvents_doNotResolveTheCall() async {
        let wire = Wire()
        let sut = CodeEditorDelegate(send: wire.send)

        async let result = sut.execute(task: "고쳐줘", workspaceId: "default", sessionId: "s1")
        await waitForSend(on: wire)
        sut.handle(.agentThinking, sessionId: "s1")
        sut.handle(.textChunk(text: "파일을 읽는 중"), sessionId: "s1")
        sut.handle(.toolCall(id: "t1", tool: "code_editor", args: nil, detail: nil), sessionId: "s1")
        sut.handle(.agentDone(ok: true, summary: "끝"), sessionId: "s1")

        let awaited = await result
        XCTAssertTrue(awaited.ok)
    }

    func test_noWorkspaceConnected_failsImmediatelyRatherThanWaitingOutTheTimeout() async {
        let wire = Wire()
        wire.isConnected = false
        let sut = CodeEditorDelegate(send: wire.send)

        let result = await sut.execute(task: "고쳐줘", workspaceId: "default", sessionId: "s1")

        XCTAssertEqual(result.error, "pet_app_disconnected")
    }

    /// Without a request_id there is nothing to tell two concurrent
    /// delegations apart, so the second is refused rather than paired with
    /// whichever agent_done lands first.
    func test_secondDelegationInTheSameSession_isRefused() async {
        let wire = Wire()
        let sut = CodeEditorDelegate(send: wire.send)

        async let first = sut.execute(task: "첫 번째", workspaceId: "default", sessionId: "s1")
        await waitForSend(on: wire)
        let second = await sut.execute(task: "두 번째", workspaceId: "default", sessionId: "s1")

        XCTAssertEqual(second.error, "execution_failed")
        XCTAssertEqual(wire.sent.count, 1, "the refused call must not reach workspace")

        sut.handle(.agentDone(ok: true, summary: "끝"), sessionId: "s1")
        let awaited = await first
        XCTAssertTrue(awaited.ok, "refusing the second must not disturb the first")
    }

    func test_cancel_releasesTheCallInsteadOfWaitingOutTheTimeout() async {
        let wire = Wire()
        let sut = CodeEditorDelegate(send: wire.send)

        async let result = sut.execute(task: "고쳐줘", workspaceId: "default", sessionId: "s1")
        await waitForSend(on: wire)
        sut.failAllInFlight(error: "cancelled", detail: "사용자가 중지했어요.")

        let awaited = await result
        XCTAssertEqual(awaited.error, "cancelled")
    }

    /// execute() suspends inside withCheckedContinuation, so the user_input is
    /// on the wire a moment after the async let starts.
    private func waitForSend(on wire: Wire) async {
        for _ in 0..<200 where wire.sent.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

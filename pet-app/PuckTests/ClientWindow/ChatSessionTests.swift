//
//  ChatSessionTests.swift
//  Puck
//
//  F13 test · owner: 박해영 (Haeyoung Park)
//  ChatSession.apply(_:) folds the same BridgeEvent stream EventRouter reads
//  for pet reactions into a chat timeline, per plan/02_pet-app.md F13's
//  "onTextChunk 스트리밍, onToolCallStart/Result를 id로 짝지은 접이식 타임라인".
//

import XCTest
@testable import Puck

final class ChatSessionTests: XCTestCase {
    private func makeSession() -> ChatSession {
        ChatSession(id: "s2", workspaceId: "w1", title: "Fix the bug", origin: .agent)
    }

    func test_initialState_isEmptyAndNotRunning() {
        let session = makeSession()
        XCTAssertEqual(session.timeline, [])
        XCTAssertFalse(session.isRunning)
        XCTAssertNil(session.pendingApproval)
    }

    func test_agentThinking_marksRunning_withNoTimelineEntry() {
        let session = makeSession()
        session.apply(.agentThinking)

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.timeline, [])
    }

    func test_textChunk_appendsANewAssistantTextEntry() {
        let session = makeSession()
        session.apply(.textChunk(text: "Running "))

        XCTAssertEqual(session.timeline.count, 1)
        guard case .assistantText(_, let text) = session.timeline[0] else {
            return XCTFail("expected assistantText, got \(session.timeline[0])")
        }
        XCTAssertEqual(text, "Running ")
    }

    /// Streaming means successive chunks concatenate onto the same entry
    /// rather than each becoming its own timeline row.
    func test_consecutiveTextChunks_concatenateIntoTheSameEntry() {
        let session = makeSession()
        session.apply(.textChunk(text: "Running "))
        session.apply(.textChunk(text: "the tests now."))

        XCTAssertEqual(session.timeline.count, 1)
        guard case .assistantText(_, let text) = session.timeline[0] else {
            return XCTFail("expected assistantText, got \(session.timeline[0])")
        }
        XCTAssertEqual(text, "Running the tests now.")
    }

    /// A tool call interrupts the streaming text -- the next chunk (if any)
    /// after a tool call must start a fresh entry, not resume the old one.
    func test_toolCallBetweenTextChunks_startsAFreshTextEntryAfterward() {
        let session = makeSession()
        session.apply(.textChunk(text: "Let me check."))
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        session.apply(.textChunk(text: "Done."))

        XCTAssertEqual(session.timeline.count, 3)
        guard case .assistantText(_, let first) = session.timeline[0] else { return XCTFail("expected assistantText") }
        XCTAssertEqual(first, "Let me check.")
        guard case .assistantText(_, let second) = session.timeline[2] else { return XCTFail("expected assistantText") }
        XCTAssertEqual(second, "Done.")
    }

    // MARK: - user's own sent messages (2026-07-29) -- ChatSession.apply(_:)
    // only ever folds in the *agent's* side of the conversation (BridgeEvent
    // is workspace -> pet-app only); without this, what the user typed would
    // never appear in their own chat view.

    func test_appendUserMessage_addsATimelineEntry() {
        let session = makeSession()
        session.appendUserMessage("hi there")

        XCTAssertEqual(session.timeline.count, 1)
        guard case .userMessage(_, let text) = session.timeline[0] else {
            return XCTFail("expected userMessage, got \(session.timeline[0])")
        }
        XCTAssertEqual(text, "hi there")
    }

    /// A user message must not be treated as the tail of a still-streaming
    /// assistant reply -- the next textChunk has to start a fresh entry.
    func test_textChunkAfterUserMessage_startsAFreshEntry_ratherThanMerging() {
        let session = makeSession()
        session.apply(.textChunk(text: "earlier reply"))
        session.appendUserMessage("interrupting question")
        session.apply(.textChunk(text: "new reply"))

        XCTAssertEqual(session.timeline.count, 3)
        guard case .assistantText(_, let last) = session.timeline[2] else { return XCTFail("expected assistantText") }
        XCTAssertEqual(last, "new reply")
    }

    func test_toolCall_appendsATimelineEntryWithItsArgs() {
        let session = makeSession()
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: .object(["command": .string("npm test")]), detail: nil))

        XCTAssertEqual(
            session.timeline,
            [.toolCall(id: "t1", tool: "run_shell", args: .object(["command": .string("npm test")]))]
        )
    }

    func test_toolResult_appendsATimelineEntryCorrelatedById() {
        let session = makeSession()
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        session.apply(.toolResult(id: "t1", ok: true, data: .object(["exit_code": .number(0)]), error: nil, detail: nil))

        XCTAssertEqual(session.timeline.count, 2)
        XCTAssertEqual(
            session.timeline[1],
            .toolResult(id: "t1", ok: true, data: .object(["exit_code": .number(0)]), error: nil, detail: nil)
        )
    }

    func test_awaitApproval_setsPendingApproval_andAppendsATimelineEntry() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "requesting to run rm -rf ./dist", approvalId: "a1"))

        XCTAssertEqual(session.pendingApproval?.approvalId, "a1")
        XCTAssertEqual(session.pendingApproval?.summary, "requesting to run rm -rf ./dist")
        XCTAssertEqual(session.timeline.count, 1)
    }

    func test_agentDone_clearsRunningAndPendingApproval_andAppendsASummaryEntry() {
        let session = makeSession()
        session.apply(.agentThinking)
        session.apply(.awaitApproval(summary: "x", approvalId: "a1"))
        session.apply(.agentDone(ok: true, summary: "3 tests passed"))

        XCTAssertFalse(session.isRunning)
        XCTAssertNil(session.pendingApproval)
        guard case .done(_, let ok, let summary)? = session.timeline.last else {
            return XCTFail("expected a done entry, got \(String(describing: session.timeline.last))")
        }
        XCTAssertTrue(ok)
        XCTAssertEqual(summary, "3 tests passed")
    }

    /// The loading row is driven by isRunning, and it has to come up on the
    /// send rather than on the relayed agent_thinking -- otherwise the window
    /// shows nothing for the whole round trip (2026-08-12).
    func test_markWaitingForAgent_startsRunningBeforeAnyEventArrives() {
        let session = makeSession()
        XCTAssertFalse(session.isRunning)

        session.markWaitingForAgent()
        XCTAssertTrue(session.isRunning)

        // And the run ending still puts it away -- a spinner with no off
        // switch is the failure mode worth guarding.
        session.apply(.agentDone(ok: true, summary: "끝"))
        XCTAssertFalse(session.isRunning)
    }

    /// A session takes as many prompts as the user types, so agent_done lands
    /// once per run, not once per session. While `.done` had a fixed id, the
    /// second one collided with the first in the transcript's ForEach and the
    /// scroll jumped to the top of the list every time a run finished.
    func test_severalRunsInOneSession_produceDistinctDoneIds() {
        let session = makeSession()
        session.apply(.agentDone(ok: true, summary: "첫 번째"))
        session.apply(.agentDone(ok: true, summary: "두 번째"))

        let doneIds = session.timeline.compactMap { entry -> AnyHashable? in
            guard case .done = entry else { return nil }
            return entry.id
        }
        XCTAssertEqual(doneIds.count, 2)
        XCTAssertEqual(Set(doneIds).count, 2, "two finished runs must not share a row identity")
    }

    /// Every timeline entry needs a stable identity for SwiftUI's List --
    /// tool call/result reuse the protocol's own tool_use id (already
    /// unique), the rest get their own.
    func test_timelineEntries_haveUniqueIds() {
        let session = makeSession()
        session.apply(.textChunk(text: "a"))
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        session.apply(.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))
        session.apply(.awaitApproval(summary: "x", approvalId: "a1"))
        session.apply(.agentDone(ok: true, summary: "done"))

        let ids = session.timeline.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - lastActivityAt / lastRunOk (v3 sidebar relative time + outcome)

    func test_lastActivityAt_isNilBeforeAnyEvent() {
        let session = makeSession()
        XCTAssertNil(session.lastActivityAt)
    }

    func test_lastActivityAt_advancesOnEveryAppliedEvent() {
        let session = makeSession()
        session.apply(.agentThinking)
        let first = session.lastActivityAt
        XCTAssertNotNil(first)
        session.apply(.textChunk(text: "hi"))
        XCTAssertNotNil(session.lastActivityAt)
        XCTAssertGreaterThanOrEqual(session.lastActivityAt!, first!)
    }

    func test_lastRunOk_isNilUntilARunCompletes() {
        let session = makeSession()
        XCTAssertNil(session.lastRunOk)
        session.apply(.agentThinking)
        XCTAssertNil(session.lastRunOk, "a run in progress has no outcome yet")
    }

    func test_lastRunOk_reflectsTheMostRecentDoneEntry() {
        let session = makeSession()
        session.apply(.agentDone(ok: false, summary: "실패"))
        XCTAssertEqual(session.lastRunOk, false)
        session.apply(.agentDone(ok: true, summary: "완료"))
        XCTAssertEqual(session.lastRunOk, true, "the newest done entry wins")
    }
}

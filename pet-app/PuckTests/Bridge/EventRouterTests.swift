//
//  EventRouterTests.swift
//  Puck
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  Verifies the event -> reaction mapping table in
//  plan/02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
//

import XCTest
@testable import Puck

final class EventRouterTests: XCTestCase {
    func test_agentThinking_transitionsToIdle() {
        let reaction = EventRouter.reaction(for: .agentThinking)
        XCTAssertEqual(reaction, EventReaction(stateTransition: .idle, emotion: "thinking"))
    }

    func test_toolCall_codeEditor_transitionsToType() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type))
    }

    // MARK: - code_editor detail.path change -> jump (02_pet-app.md F3:
    // "detail.path 변경 시 짧은 점프") -- decoded via EventReaction.jump but
    // never actually checked for a change until now (found via spec
    // cross-check).

    func test_toolCall_codeEditor_firstEventEver_doesNotJump() {
        // Nothing to compare the very first path against -- entering Type
        // isn't itself a "change".
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: .object(["path": .string("src/main.ts")])),
            previousCodeEditorPath: nil
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: false))
    }

    func test_toolCall_codeEditor_samePathAsBefore_doesNotJump() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: .object(["path": .string("src/main.ts")])),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: false))
    }

    func test_toolCall_codeEditor_differentPathThanBefore_jumps() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: .object(["path": .string("src/other.ts")])),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: true))
    }

    func test_toolCall_runShell_neverJumpsRegardlessOfPreviousPath() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, jump: false))
    }

    func test_toolCall_runShell_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolCall_runAppleScript_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "run_applescript", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolResult_failure_reactsWithTaskFailSFX() {
        let reaction = EventRouter.reaction(for: .toolResult(id: "t1", ok: false, data: nil, error: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .reactClick, sfxKey: "task_fail", emotion: "sad"))
    }

    func test_toolResult_success_isNoOp() {
        let reaction = EventRouter.reaction(for: .toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction())
    }

    func test_awaitApproval_transitionsToPointWithWaitingSFX() {
        let reaction = EventRouter.reaction(for: .awaitApproval(summary: "rm -rf ./dist", approvalId: "a1"))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, sfxKey: "await_approval", emotion: "thinking"))
    }

    func test_agentDone_success_triggersSuccessSFXJumpAndBubble() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: "3 tests passed"))
        XCTAssertEqual(
            reaction,
            EventReaction(sfxKey: "task_success", jump: true, bubbleText: "3 tests passed", emotion: "happy")
        )
    }

    /// The bubble is one line beside a 100px character, and agent_done's
    /// summary is whatever the producing agent put there -- for the F15 local
    /// agent, the entire reply. The bubble should keep only the headline, not
    /// dump the whole answer. The full text is in the transcript either way.
    func test_agentDone_bubbleKeepsOnlyTheHeadline() {
        let wall = """
        hello.ts에 주석을 추가했어요. 파일 맨 위에 한 줄 주석을 넣었고, \
        나머지 코드는 손대지 않았습니다.
        추가로 확인이 필요하면 말씀해 주세요.
        """
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: wall))

        XCTAssertEqual(reaction.bubbleText, "hello.ts에 주석을 추가했어요.")
    }

    func test_bubbleSummary_edges() {
        // No sentence terminator: capped with an ellipsis rather than cut mid-air.
        let long = String(repeating: "가", count: 80)
        XCTAssertEqual(EventRouter.bubbleSummary(from: long), String(repeating: "가", count: 60) + "…")
        // Nothing to say means no bubble at all, not an empty one.
        XCTAssertNil(EventRouter.bubbleSummary(from: "   \n  "))
        // Already short: untouched, terminator kept.
        XCTAssertEqual(EventRouter.bubbleSummary(from: "Safari 켰어요!"), "Safari 켰어요!")
    }

    func test_agentDone_failure_isNoOp() {
        // Not specified in the reaction table — only agent_done(ok=true) is; toolResult(ok=false)
        // already covers the failure-signaling case.
        let reaction = EventRouter.reaction(for: .agentDone(ok: false, summary: "failed"))
        XCTAssertEqual(reaction, EventReaction())
    }
}

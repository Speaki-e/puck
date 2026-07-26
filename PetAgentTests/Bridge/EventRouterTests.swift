//
//  EventRouterTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  Verifies the event -> reaction mapping table in
//  plan/02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
//

import XCTest
@testable import PetAgent

final class EventRouterTests: XCTestCase {
    func test_agentThinking_transitionsToIdle() {
        let reaction = EventRouter.reaction(for: .agentThinking)
        XCTAssertEqual(reaction, EventReaction(stateTransition: .idle))
    }

    func test_toolCall_codeEditor_transitionsToType() {
        let reaction = EventRouter.reaction(for: .toolCall(tool: "code_editor", detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type))
    }

    func test_toolCall_runShell_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(tool: "run_shell", detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolCall_runAppleScript_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(tool: "run_applescript", detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolResult_failure_reactsWithTaskFailSFX() {
        let reaction = EventRouter.reaction(for: .toolResult(ok: false))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .reactClick, sfxKey: "task_fail"))
    }

    func test_toolResult_success_isNoOp() {
        let reaction = EventRouter.reaction(for: .toolResult(ok: true))
        XCTAssertEqual(reaction, EventReaction())
    }

    func test_awaitApproval_transitionsToPointWithWaitingSFX() {
        let reaction = EventRouter.reaction(for: .awaitApproval(summary: "rm -rf ./dist"))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, sfxKey: "await_approval"))
    }

    func test_agentDone_success_triggersSuccessSFXJumpAndBubble() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: "3 tests passed"))
        XCTAssertEqual(
            reaction,
            EventReaction(sfxKey: "task_success", jump: true, bubbleText: "3 tests passed")
        )
    }

    func test_agentDone_failure_isNoOp() {
        // Not specified in the reaction table — only agent_done(ok=true) is; toolResult(ok=false)
        // already covers the failure-signaling case.
        let reaction = EventRouter.reaction(for: .agentDone(ok: false, summary: "failed"))
        XCTAssertEqual(reaction, EventReaction())
    }
}
